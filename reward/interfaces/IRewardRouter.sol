// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IRewardRouter {
    function stakeKpe(uint256 _amount) external;
    
    function stakeEsKpe(uint256 _amount) external;

    function unstakeKpe(uint256 _amount) external;

    function unstakeEsKpe(uint256 _amount) external;

    function signalTransfer(address _receiver) external;

    function compound() external;

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
    ) external returns (uint256 amountOut);
}
