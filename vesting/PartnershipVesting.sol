// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../libraries/token/IERC20.sol";
import "../reward/interfaces/IRewardRouter.sol";
import "../reward/interfaces/IRewardTracker.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/access/Ownable.sol";
import "../libraries/math/SafeMath.sol";

contract PartnershipVesting is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 private _start;
    uint256 private _cliff;

    address private _kpe;
    address private _rewardRouter;
    address private _kpeTracker;

    event TokensReleased(address token, uint256 amount);

    constructor(
        address kpe,
        address rewardRouter,
        address kpeTracker,
        uint256 start,
        uint256 cliffDuration
    ) public {
        _start = start;
        _cliff = start.add(cliffDuration);

        _kpe = kpe;
        _rewardRouter = rewardRouter;
        _kpeTracker = kpeTracker;
    }

    function cliff() public view returns (uint256) {
        return _cliff;
    }

    function start() public view returns (uint256) {
        return _start;
    }

    function kpe() public view returns (address) {
        return _kpe;
    }

    function rewardRouter() public view returns (address) {
        return _rewardRouter;
    }

    function setRewardRouter(address newRewardRouter) public onlyOwner {
        require(newRewardRouter != address(0), "Invalid address");

        _rewardRouter = newRewardRouter;
    }

    function setRewardTracker(address rewardTracker) public onlyOwner {
        require(rewardTracker != address(0), "Invalid address");

        _kpeTracker = rewardTracker;
    }

    function approveToken(
        address _token,
        address _to,
        uint256 _amount
    ) external onlyOwner {
        require(IERC20(_token).approve(_to, _amount), "Approve failed.");
    }

    function stakeToken() public onlyOwner {
        uint256 kpeAmount = IERC20(_kpe).balanceOf(address(this));

        if (kpeAmount > 0) {
            IERC20(_kpe).approve(_kpeTracker, kpeAmount);
            IRewardRouter(_rewardRouter).stakeKpe(kpeAmount);
        }
    }

    /**
        1 - convert rewards into MATIC (receives MATICs)
        2 - buy and stake KPE with rewards
     */
    function compound(uint256 compoundType) public onlyOwner {
        require(compoundType > 0 && compoundType < 3, "PartnershipVesting: Not in range");

        bool _shouldConvertWethToEth = compoundType == 1;
        bool _shouldConvertKpeAndStake = compoundType == 2;

        IRewardRouter(_rewardRouter).handleRewards(
            false, // _shouldClaimKpe,
            false, // _shouldStakeKpe,
            true, // _shouldClaimEsKpe,
            true, // _shouldStakeEsKpe,
            true, // _shouldStakeMultiplierPoints
            true, // _shouldClaimWeth,
            _shouldConvertWethToEth,
            false,
            _shouldConvertKpeAndStake
        );

        if (_shouldConvertWethToEth) {
            (bool success, ) = owner().call{value: address(this).balance}("");
            require(success, "Transfer failed!");
        }
    }

    function withdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Transfer failed!");
    }

    function transferAccount(address account) public onlyOwner {
        require(block.timestamp > _cliff, "PartnershipVesting: Timelock not passed");

        IRewardRouter(_rewardRouter).signalTransfer(account);
    }

    receive() external payable {}
}
