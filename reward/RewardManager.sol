// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "../access/Governable.sol";
import "../peripherals/interfaces/ITimelock.sol";

contract RewardManager is Governable {
    bool public isInitialized;

    ITimelock public timelock;
    address public rewardRouter;

    address public klpManager;

    address public stakedKpeTracker;
    address public bonusKpeTracker;
    address public feeKpeTracker;

    address public feeKlpTracker;
    address public stakedKlpTracker;

    address public stakedKpeDistributor;
    address public stakedKlpDistributor;

    address public esKpe;
    address public bnKpe;

    address public kpeVester;
    address public klpVester;

    function initialize(
        ITimelock _timelock,
        address _rewardRouter,
        address _klpManager,
        address _stakedKpeTracker,
        address _bonusKpeTracker,
        address _feeKpeTracker,
        address _feeKlpTracker,
        address _stakedKlpTracker,
        address _stakedKpeDistributor,
        address _stakedKlpDistributor,
        address _esKpe,
        address _bnKpe,
        address _kpeVester,
        address _klpVester
    ) external onlyGov {
        require(!isInitialized, "RewardManager: already initialized");
        isInitialized = true;

        timelock = _timelock;
        rewardRouter = _rewardRouter;

        klpManager = _klpManager;

        stakedKpeTracker = _stakedKpeTracker;
        bonusKpeTracker = _bonusKpeTracker;
        feeKpeTracker = _feeKpeTracker;

        feeKlpTracker = _feeKlpTracker;
        stakedKlpTracker = _stakedKlpTracker;

        stakedKpeDistributor = _stakedKpeDistributor;
        stakedKlpDistributor = _stakedKlpDistributor;

        esKpe = _esKpe;
        bnKpe = _bnKpe;

        kpeVester = _kpeVester;
        klpVester = _klpVester;
    }

    // function updateEsKpeHandlers() external onlyGov {
    //     timelock.managedSetHandler(esKpe, rewardRouter, true);

    //     timelock.managedSetHandler(esKpe, stakedKpeDistributor, true);
    //     timelock.managedSetHandler(esKpe, stakedKlpDistributor, true);

    //     timelock.managedSetHandler(esKpe, stakedKpeTracker, true);
    //     timelock.managedSetHandler(esKpe, stakedKlpTracker, true);

    //     timelock.managedSetHandler(esKpe, kpeVester, true);
    //     timelock.managedSetHandler(esKpe, klpVester, true);
    // }

    // function enableRewardRouter() external onlyGov {
    //     timelock.managedSetHandler(klpManager, rewardRouter, true);

    //     timelock.managedSetHandler(stakedKpeTracker, rewardRouter, true);
    //     timelock.managedSetHandler(bonusKpeTracker, rewardRouter, true);
    //     timelock.managedSetHandler(feeKpeTracker, rewardRouter, true);

    //     timelock.managedSetHandler(feeKlpTracker, rewardRouter, true);
    //     timelock.managedSetHandler(stakedKlpTracker, rewardRouter, true);

    //     timelock.managedSetHandler(esKpe, rewardRouter, true);

    //     timelock.managedSetMinter(bnKpe, rewardRouter, true);

    //     timelock.managedSetMinter(esKpe, kpeVester, true);
    //     timelock.managedSetMinter(esKpe, klpVester, true);

    //     timelock.managedSetHandler(kpeVester, rewardRouter, true);
    //     timelock.managedSetHandler(klpVester, rewardRouter, true);

    //     timelock.managedSetHandler(feeKpeTracker, kpeVester, true);
    //     timelock.managedSetHandler(stakedKlpTracker, klpVester, true);
    // }
}
