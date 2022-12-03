// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IKlpManager {
    function usdk() external view returns (address);
    function cooldownDuration() external returns (uint256);
    function setCooldownDuration(uint256 _cooldownDuration) external;

    function lastAddedAt(address _account) external returns (uint256);

    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minUsdk,
        uint256 _minKlp
    ) external returns (uint256);

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minUsdk,
        uint256 _minKlp
    ) external returns (uint256);

    function removeLiquidity(
        address _tokenOut,
        uint256 _klpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _klpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);
}