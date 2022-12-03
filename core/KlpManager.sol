// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/utils/ReentrancyGuard.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IKlpManager.sol";
import "../tokens/interfaces/IUSDK.sol";
import "../tokens/interfaces/IMintable.sol";
import "../access/Governable.sol";

contract KlpManager is ReentrancyGuard, Governable, IKlpManager {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_PRECISION = 10**30;
    uint256 public constant USDK_DECIMALS = 18;
    uint256 public constant MAX_COOLDOWN_DURATION = 48 hours;

    IVault public vault;
    address public override usdk;
    address public klp;

    uint256 public override cooldownDuration;
    mapping(address => uint256) public override lastAddedAt;

    uint256 public aumAddition;
    uint256 public aumDeduction;

    bool public inPrivateMode;
    mapping(address => bool) public isHandler;

    event AddLiquidity(address account, address token, uint256 amount, uint256 aumInUsdk, uint256 klpSupply, uint256 usdkAmount, uint256 mintAmount);

    event RemoveLiquidity(address account, address token, uint256 klpAmount, uint256 aumInUsdk, uint256 klpSupply, uint256 usdkAmount, uint256 amountOut);

    constructor(
        address _vault,
        address _usdk,
        address _klp,
        uint256 _cooldownDuration
    ) public {
        gov = msg.sender;
        vault = IVault(_vault);
        usdk = _usdk;
        klp = _klp;
        cooldownDuration = _cooldownDuration;
    }

    function setInPrivateMode(bool _inPrivateMode) external onlyGov {
        inPrivateMode = _inPrivateMode;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    function setCooldownDuration(uint256 _cooldownDuration) external override onlyGov {
        require(_cooldownDuration <= MAX_COOLDOWN_DURATION, "KlpManager: invalid _cooldownDuration");
        cooldownDuration = _cooldownDuration;
    }

    function setAumAdjustment(uint256 _aumAddition, uint256 _aumDeduction) external onlyGov {
        aumAddition = _aumAddition;
        aumDeduction = _aumDeduction;
    }

    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minUsdk,
        uint256 _minKlp
    ) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert("KlpManager: action not enabled");
        }
        return _addLiquidity(msg.sender, msg.sender, _token, _amount, _minUsdk, _minKlp);
    }

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdk,
        uint256 _minKlp
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _addLiquidity(_fundingAccount, _account, _token, _amount, _minUsdk, _minKlp);
    }

    function removeLiquidity(
        address _tokenOut,
        uint256 _klpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        if (inPrivateMode) {
            revert("KlpManager: action not enabled");
        }
        return _removeLiquidity(msg.sender, _tokenOut, _klpAmount, _minOut, _receiver);
    }

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _klpAmount,
        uint256 _minOut,
        address _receiver
    ) external override nonReentrant returns (uint256) {
        _validateHandler();
        return _removeLiquidity(_account, _tokenOut, _klpAmount, _minOut, _receiver);
    }

    function getAums() public view returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = getAum(true);
        amounts[1] = getAum(false);
        return amounts;
    }

    function getAumInUsdk(bool maximise) public view returns (uint256) {
        uint256 aum = getAum(maximise);
        return aum.mul(10**USDK_DECIMALS).div(PRICE_PRECISION);
    }

    function getAum(bool maximise) public view returns (uint256) {
        uint256 length = vault.allWhitelistedTokensLength();
        uint256 aum = aumAddition;
        uint256 shortProfits = 0;

        for (uint256 i = 0; i < length; i++) {
            address token = vault.allWhitelistedTokens(i);
            bool isWhitelisted = vault.whitelistedTokens(token);

            if (!isWhitelisted) {
                continue;
            }

            uint256 price = maximise ? vault.getMaxPrice(token) : vault.getMinPrice(token);
            uint256 poolAmount = vault.poolAmounts(token);
            uint256 decimals = vault.tokenDecimals(token);

            if (vault.stableTokens(token)) {
                aum = aum.add(poolAmount.mul(price).div(10**decimals));
            } else {
                // add global short profit / loss
                uint256 size = vault.globalShortSizes(token);
                if (size > 0) {
                    uint256 averagePrice = vault.globalShortAveragePrices(token);
                    uint256 priceDelta = averagePrice > price ? averagePrice.sub(price) : price.sub(averagePrice);
                    uint256 delta = size.mul(priceDelta).div(averagePrice);
                    if (price > averagePrice) {
                        // add losses from shorts
                        aum = aum.add(delta);
                    } else {
                        shortProfits = shortProfits.add(delta);
                    }
                }

                aum = aum.add(vault.guaranteedUsd(token));

                uint256 reservedAmount = vault.reservedAmounts(token);
                aum = aum.add(poolAmount.sub(reservedAmount).mul(price).div(10**decimals));
            }
        }

        aum = shortProfits > aum ? 0 : aum.sub(shortProfits);
        return aumDeduction > aum ? 0 : aum.sub(aumDeduction);
    }

    function _addLiquidity(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdk,
        uint256 _minKlp
    ) private returns (uint256) {
        require(_amount > 0, "KlpManager: invalid _amount");

        // calculate aum before buyUSDK
        uint256 aumInUsdk = getAumInUsdk(true);
        uint256 klpSupply = IERC20(klp).totalSupply();

        IERC20(_token).safeTransferFrom(_fundingAccount, address(vault), _amount);
        uint256 usdkAmount = vault.buyUSDK(_token, address(this));
        require(usdkAmount >= _minUsdk, "KlpManager: insufficient USDK output");

        uint256 mintAmount = aumInUsdk == 0 ? usdkAmount : usdkAmount.mul(klpSupply).div(aumInUsdk);
        require(mintAmount >= _minKlp, "KlpManager: insufficient KLP output");

        IMintable(klp).mint(_account, mintAmount);

        lastAddedAt[_account] = block.timestamp;

        emit AddLiquidity(_account, _token, _amount, aumInUsdk, klpSupply, usdkAmount, mintAmount);

        return mintAmount;
    }

    function _removeLiquidity(
        address _account,
        address _tokenOut,
        uint256 _klpAmount,
        uint256 _minOut,
        address _receiver
    ) private returns (uint256) {
        require(_klpAmount > 0, "KlpManager: invalid _klpAmount");
        require(lastAddedAt[_account].add(cooldownDuration) <= block.timestamp, "KlpManager: cooldown duration not yet passed");

        // calculate aum before sellUSDK
        uint256 aumInUsdk = getAumInUsdk(false);
        uint256 klpSupply = IERC20(klp).totalSupply();

        uint256 usdkAmount = _klpAmount.mul(aumInUsdk).div(klpSupply);
        uint256 usdkBalance = IERC20(usdk).balanceOf(address(this));
        if (usdkAmount > usdkBalance) {
            IUSDK(usdk).mint(address(this), usdkAmount.sub(usdkBalance));
        }

        IMintable(klp).burn(_account, _klpAmount);

        IERC20(usdk).transfer(address(vault), usdkAmount);
        uint256 amountOut = vault.sellUSDK(_tokenOut, _receiver);
        require(amountOut >= _minOut, "KlpManager: insufficient output");

        emit RemoveLiquidity(_account, _tokenOut, _klpAmount, aumInUsdk, klpSupply, usdkAmount, amountOut);

        return amountOut;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "KlpManager: forbidden");
    }
}
