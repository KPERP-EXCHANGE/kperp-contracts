// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/token/TransferHelper.sol";
import "../libraries/utils/ReentrancyGuard.sol";
import "../libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "../tokens/interfaces/IMintable.sol";
import "../tokens/interfaces/IWETH.sol";
import "../core/interfaces/IKlpManager.sol";
import "../core/interfaces/IVault.sol";
import "../access/Governable.sol";
import "../peripherals/interfaces/ISwapRouter.sol";
import "../peripherals/interfaces/IUniswapV2Router.sol";

contract RewardRouter is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;


    ISwapRouter public  swapRouter;
    IUniswapV2Router public  uniswapV2Router;

    bool public isUniswapV3;

    address public vault;
    address public usdc;
    address public kpe;
    address public esKpe;
    address public bnKpe;

    address public klp; // KPE Liquidity Provider token

    address public stakedKpeTracker;
    address public bonusKpeTracker;
    address public feeKpeTracker;

    address public stakedKlpTracker;
    address public feeKlpTracker;

    address public klpManager;

    address public kpeVester;
    address public klpVester;

    mapping(address => address) public pendingReceivers;

    event StakeKpe(address account, address token, uint256 amount);
    event UnstakeKpe(address account, address token, uint256 amount);

    event StakeKlp(address account, uint256 amount);
    event UnstakeKlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    uint24 public constant KPE_USDC_POOL_FEE = 10000;

    constructor(address _swapRouter,
        address _weth,
        address _kpe,
        address _esKpe,
        address _bnKpe,
        address _klp,       
        address _usdc,
        address _vault,
        bool _isUniswapV3    
    ) public{        
        weth = _weth;
        kpe = _kpe;
        esKpe = _esKpe;
        bnKpe = _bnKpe;
        klp = _klp;        
        usdc = _usdc;
        vault = _vault;
        isUniswapV3 = _isUniswapV3;
        if(isUniswapV3)
            swapRouter = ISwapRouter(_swapRouter);
        else    
            uniswapV2Router = IUniswapV2Router(_swapRouter);

    }

    function initialize(
        address _stakedKpeTracker,
        address _bonusKpeTracker,
        address _feeKpeTracker,
        address _feeKlpTracker,
        address _stakedKlpTracker,
        address _klpManager,
        address _kpeVester,
        address _klpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        stakedKpeTracker = _stakedKpeTracker;
        bonusKpeTracker = _bonusKpeTracker;
        feeKpeTracker = _feeKpeTracker;

        feeKlpTracker = _feeKlpTracker;
        stakedKlpTracker = _stakedKlpTracker;

        klpManager = _klpManager;

        kpeVester = _kpeVester;
        klpVester = _klpVester;

    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function setSwapRouter(address _swapRouter,bool _isUniswapV3) external onlyGov {
        isUniswapV3 = _isUniswapV3;
        if(isUniswapV3)
            swapRouter = ISwapRouter(_swapRouter);
        else    
            uniswapV2Router = IUniswapV2Router(_swapRouter);
    }

    function batchStakeKpeForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _kpe = kpe;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeKpe(msg.sender, _accounts[i], _kpe, _amounts[i]);
        }
    }

    function stakeKpeForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeKpe(msg.sender, _account, kpe, _amount);
    }

    function stakeKpe(uint256 _amount) external nonReentrant {
        _stakeKpe(msg.sender, msg.sender, kpe, _amount);
    }

    function stakeEsKpe(uint256 _amount) external nonReentrant {
        _stakeKpe(msg.sender, msg.sender, esKpe, _amount);
    }

    function unstakeKpe(uint256 _amount) external nonReentrant {
        _unstakeKpe(msg.sender, kpe, _amount, true);
    }

    function unstakeEsKpe(uint256 _amount) external nonReentrant {
        _unstakeKpe(msg.sender, esKpe, _amount, true);
    }

    function mintAndStakeKlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdk,
        uint256 _minKlp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 klpAmount = IKlpManager(klpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdk, _minKlp);
        IRewardTracker(feeKlpTracker).stakeForAccount(account, account, klp, klpAmount);
        IRewardTracker(stakedKlpTracker).stakeForAccount(account, account, feeKlpTracker, klpAmount);

        emit StakeKlp(account, klpAmount);

        return klpAmount;
    }

    function mintAndStakeKlpETH(uint256 _minUsdk, uint256 _minKlp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        return _mintAndStakeKlpETH(msg.value,_minUsdk, _minKlp);
    }

    function _mintAndStakeKlpETH(uint256 _amount,uint256 _minUsdk, uint256 _minKlp) private returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IERC20(weth).approve(klpManager, _amount);

        address account = msg.sender;
        uint256 klpAmount = IKlpManager(klpManager).addLiquidityForAccount(address(this), account, weth, _amount, _minUsdk, _minKlp);

        IRewardTracker(feeKlpTracker).stakeForAccount(account, account, klp, klpAmount);
        IRewardTracker(stakedKlpTracker).stakeForAccount(account, account, feeKlpTracker, klpAmount);

        emit StakeKlp(account, klpAmount);

        return klpAmount;
    }

    function unstakeAndRedeemKlp(
        address _tokenOut,
        uint256 _klpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_klpAmount > 0, "RewardRouter: invalid _klpAmount");

        address account = msg.sender;
        IRewardTracker(stakedKlpTracker).unstakeForAccount(account, feeKlpTracker, _klpAmount, account);
        IRewardTracker(feeKlpTracker).unstakeForAccount(account, klp, _klpAmount, account);
        uint256 amountOut = IKlpManager(klpManager).removeLiquidityForAccount(account, _tokenOut, _klpAmount, _minOut, _receiver);

        emit UnstakeKlp(account, _klpAmount);

        return amountOut;
    }

    function unstakeAndRedeemKlpETH(
        uint256 _klpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        require(_klpAmount > 0, "RewardRouter: invalid _klpAmount");

        address account = msg.sender;
        IRewardTracker(stakedKlpTracker).unstakeForAccount(account, feeKlpTracker, _klpAmount, account);
        IRewardTracker(feeKlpTracker).unstakeForAccount(account, klp, _klpAmount, account);
        uint256 amountOut = IKlpManager(klpManager).removeLiquidityForAccount(account, weth, _klpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeKlp(account, _klpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeKpeTracker).claimForAccount(account, account);
        IRewardTracker(feeKlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedKpeTracker).claimForAccount(account, account);
        IRewardTracker(stakedKlpTracker).claimForAccount(account, account);
    }

    function claimEsKpe() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedKpeTracker).claimForAccount(account, account);
        IRewardTracker(stakedKlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeKpeTracker).claimForAccount(account, account);
        IRewardTracker(feeKlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimKpe,
        bool _shouldStakeKpe,
        bool _shouldClaimEsKpe,
        bool _shouldStakeEsKpe,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth,
        bool _shouldAddIntoKLP,
        bool _shouldConvertKpeAndStake
    ) external nonReentrant returns (uint256 amountOut) {
        address account = msg.sender;

        uint256 kpeAmount = 0;
        if (_shouldClaimKpe) {
            uint256 kpeAmount0 = IVester(kpeVester).claimForAccount(account, account);
            uint256 kpeAmount1 = IVester(klpVester).claimForAccount(account, account);
            kpeAmount = kpeAmount0.add(kpeAmount1);
        }

        if (_shouldStakeKpe && kpeAmount > 0) {
            _stakeKpe(account, account, kpe, kpeAmount);
        }

        uint256 esKpeAmount = 0;
        if (_shouldClaimEsKpe) {
            uint256 esKpeAmount0 = IRewardTracker(stakedKpeTracker).claimForAccount(account, account);
            uint256 esKpeAmount1 = IRewardTracker(stakedKlpTracker).claimForAccount(account, account);
            esKpeAmount = esKpeAmount0.add(esKpeAmount1);
        }

        if (_shouldStakeEsKpe && esKpeAmount > 0) {
            _stakeKpe(account, account, esKpe, esKpeAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnKpeAmount = IRewardTracker(bonusKpeTracker).claimForAccount(account, account);
            if (bnKpeAmount > 0) {
                IRewardTracker(feeKpeTracker).stakeForAccount(account, account, bnKpe, bnKpeAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth || _shouldAddIntoKLP || _shouldConvertKpeAndStake) {
                uint256 weth0 = IRewardTracker(feeKpeTracker).claimForAccount(account, address(this));
                uint256 weth1 = IRewardTracker(feeKlpTracker).claimForAccount(account, address(this));

                uint256 wethAmount = weth0.add(weth1);
                

                if(_shouldAddIntoKLP){
                    amountOut = _mintAndStakeKlpETH(wethAmount,0,0);
                }else if(_shouldConvertKpeAndStake){
                    //convert weth->usdc->kpe and stake

                    IERC20(weth).safeTransfer(vault, wethAmount);

                    //convert weth->usdc via vault
                    uint256 usdcAmountOut = IVault(vault).swap(weth, usdc, address(this));

                    //convert usdc->kpe via uniswap
                     uint256 kpeAmountOut = _swapExactInputSingle(usdcAmountOut);

                    if (kpeAmountOut > 0) {
                        TransferHelper.safeApprove(kpe, stakedKpeTracker, kpeAmountOut);
                        _stakeKpe(address(this), account, kpe, kpeAmountOut);
                        amountOut = kpeAmountOut;
                    }

                }else{
                    IWETH(weth).withdraw(wethAmount);
                    payable(account).sendValue(wethAmount);
                }
            } else {
                IRewardTracker(feeKpeTracker).claimForAccount(account, account);
                IRewardTracker(feeKlpTracker).claimForAccount(account, account);
            }
        }
    }

    function _swapExactInputSingle(uint256 amountIn) private returns (uint256 amountOut) {

        if (isUniswapV3){
            TransferHelper.safeApprove(usdc, address(swapRouter), amountIn);

            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: usdc,
                    tokenOut: kpe,
                    fee: KPE_USDC_POOL_FEE,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                });

            amountOut = swapRouter.exactInputSingle(params);
        }else{
            TransferHelper.safeApprove(usdc, address(uniswapV2Router), amountIn);

            address[] memory path = new address[](2);
            path[0] = usdc;
            path[1] = kpe;

            amountOut = uniswapV2Router.swapExactTokensForTokens(
                amountIn,
                1,
                path,
                address(this),
                block.timestamp
            )[1];

        }
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(IERC20(kpeVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(klpVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(kpeVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(klpVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedKpe = IRewardTracker(stakedKpeTracker).depositBalances(_sender, kpe);
        if (stakedKpe > 0) {
            _unstakeKpe(_sender, kpe, stakedKpe, false);
            _stakeKpe(_sender, receiver, kpe, stakedKpe);
        }

        uint256 stakedEsKpe = IRewardTracker(stakedKpeTracker).depositBalances(_sender, esKpe);
        if (stakedEsKpe > 0) {
            _unstakeKpe(_sender, esKpe, stakedEsKpe, false);
            _stakeKpe(_sender, receiver, esKpe, stakedEsKpe);
        }

        uint256 stakedBnKpe = IRewardTracker(feeKpeTracker).depositBalances(_sender, bnKpe);
        if (stakedBnKpe > 0) {
            IRewardTracker(feeKpeTracker).unstakeForAccount(_sender, bnKpe, stakedBnKpe, _sender);
            IRewardTracker(feeKpeTracker).stakeForAccount(_sender, receiver, bnKpe, stakedBnKpe);
        }

        uint256 esKpeBalance = IERC20(esKpe).balanceOf(_sender);
        if (esKpeBalance > 0) {
            IERC20(esKpe).transferFrom(_sender, receiver, esKpeBalance);
        }

        uint256 klpAmount = IRewardTracker(feeKlpTracker).depositBalances(_sender, klp);
        if (klpAmount > 0) {
            IRewardTracker(stakedKlpTracker).unstakeForAccount(_sender, feeKlpTracker, klpAmount, _sender);
            IRewardTracker(feeKlpTracker).unstakeForAccount(_sender, klp, klpAmount, _sender);

            IRewardTracker(feeKlpTracker).stakeForAccount(_sender, receiver, klp, klpAmount);
            IRewardTracker(stakedKlpTracker).stakeForAccount(receiver, receiver, feeKlpTracker, klpAmount);
        }

        IVester(kpeVester).transferStakeValues(_sender, receiver);
        IVester(klpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(IRewardTracker(stakedKpeTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedKpeTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedKpeTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedKpeTracker.cumulativeRewards > 0");

        require(IRewardTracker(bonusKpeTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: bonusKpeTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusKpeTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: bonusKpeTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeKpeTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeKpeTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeKpeTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeKpeTracker.cumulativeRewards > 0");

        require(IVester(kpeVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: kpeVester.transferredAverageStakedAmounts > 0");
        require(IVester(kpeVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: kpeVester.transferredCumulativeRewards > 0");

        require(IRewardTracker(stakedKlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedKlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedKlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedKlpTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeKlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeKlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeKlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeKlpTracker.cumulativeRewards > 0");

        require(IVester(klpVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: kpeVester.transferredAverageStakedAmounts > 0");
        require(IVester(klpVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: kpeVester.transferredCumulativeRewards > 0");

        require(IERC20(kpeVester).balanceOf(_receiver) == 0, "RewardRouter: kpeVester.balance > 0");
        require(IERC20(klpVester).balanceOf(_receiver) == 0, "RewardRouter: klpVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundKpe(_account);
        _compoundKlp(_account);
    }

    function _compoundKpe(address _account) private {
        uint256 esKpeAmount = IRewardTracker(stakedKpeTracker).claimForAccount(_account, _account);
        if (esKpeAmount > 0) {
            _stakeKpe(_account, _account, esKpe, esKpeAmount);
        }

        uint256 bnKpeAmount = IRewardTracker(bonusKpeTracker).claimForAccount(_account, _account);
        if (bnKpeAmount > 0) {
            IRewardTracker(feeKpeTracker).stakeForAccount(_account, _account, bnKpe, bnKpeAmount);
        }
    }

    function _compoundKlp(address _account) private {
        uint256 esKpeAmount = IRewardTracker(stakedKlpTracker).claimForAccount(_account, _account);
        if (esKpeAmount > 0) {
            _stakeKpe(_account, _account, esKpe, esKpeAmount);
        }
    }

    function _stakeKpe(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedKpeTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusKpeTracker).stakeForAccount(_account, _account, stakedKpeTracker, _amount);
        IRewardTracker(feeKpeTracker).stakeForAccount(_account, _account, bonusKpeTracker, _amount);

        emit StakeKpe(_account, _token, _amount);
    }

    function _unstakeKpe(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnKpe
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedKpeTracker).stakedAmounts(_account);

        IRewardTracker(feeKpeTracker).unstakeForAccount(_account, bonusKpeTracker, _amount, _account);
        IRewardTracker(bonusKpeTracker).unstakeForAccount(_account, stakedKpeTracker, _amount, _account);
        IRewardTracker(stakedKpeTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnKpe) {
            uint256 bnKpeAmount = IRewardTracker(bonusKpeTracker).claimForAccount(_account, _account);
            if (bnKpeAmount > 0) {
                IRewardTracker(feeKpeTracker).stakeForAccount(_account, _account, bnKpe, bnKpeAmount);
            }

            uint256 stakedBnKpe = IRewardTracker(feeKpeTracker).depositBalances(_account, bnKpe);
            if (stakedBnKpe > 0) {
                uint256 reductionAmount = stakedBnKpe.mul(_amount).div(balance);
                IRewardTracker(feeKpeTracker).unstakeForAccount(_account, bnKpe, reductionAmount, _account);
                IMintable(bnKpe).burn(_account, reductionAmount);
            }
        }

        emit UnstakeKpe(_account, _token, _amount);
    }
}
