// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardDistributor.sol";
import "./BonusDistributor.sol";

contract StakedKpeDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}

contract BonusKpeDistributor is BonusDistributor {
    constructor(address _rewardToken, address _rewardTracker) public BonusDistributor(_rewardToken, _rewardTracker) {}
}

contract FeeKpeDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}

contract StakedKlpDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}

contract FeeKlpDistributor is RewardDistributor {
    constructor(address _rewardToken, address _rewardTracker) public RewardDistributor(_rewardToken, _rewardTracker) {}
}
