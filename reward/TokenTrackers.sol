// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./RewardTracker.sol";

contract StakedKpeTracker is RewardTracker {
    constructor() public RewardTracker("Staked KPE", "sKPE") {}
}

contract BonusKpeTracker is RewardTracker {
    constructor() public RewardTracker("Staked + Bonus KPE", "sbKPE") {}
}

contract FeeKpeTracker is RewardTracker {
    constructor() public RewardTracker("Staked + Bonus + Fee KPE", "sbfKPE") {}
}

contract StakedKlpTracker is RewardTracker {
    constructor() public RewardTracker("Fee + Staked KLP", "fsKLP") {}
}

contract FeeKlpTracker is RewardTracker {
    constructor() public RewardTracker("Fee KLP", "fKLP") {}
}
