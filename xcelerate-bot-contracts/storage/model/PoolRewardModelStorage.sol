// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../TitanCoreStorage.sol";
import "../../interfaces/v1/IPoolGuardian.sol";
import "../../oracles/IPriceOracle.sol";
import "../../interfaces/governance/ICommittee.sol";

contract PoolRewardModelStorage is TitanCoreStorage {
    using EnumerableSet for EnumerableSet.UintSet;

    struct PoolInfo {
        uint64 allocPoint;
        uint64 multiplier;
        uint64 lastRewardBlock;
        uint256 accIPISTRPerShare;
        uint256 accStablePerShare;
    }

    struct RewardDebtInfo {
        uint256 poolIpistrRewardDebt;
        uint256 poolStableRewardDebt;
        uint256 voterIpistrRewardDebt;
        uint256 voterStableRewardDebt;
        uint256 creatorIpistrRewardDebt;
        uint256 creatorStableRewardDebt;
    }

    IPoolGuardian public poolGuardian;
    IPriceOracle public priceOracle;
    ICommittee public committee;
    address public ipistrToken;
    address public farming;

    bool internal _initialized;

    // Count of IPISTR produces per block
    uint256 public ipistrPerBlock;

    // Pool totalWeight
    uint256 public totalAllocWeight;

    uint256 internal constant IPISTR_DECIMAL_SCALER = 1e12;

    // poolId => (userAddr => rewardDebt) on basePool
    mapping(uint256 => mapping(address => uint256)) public baseRewardDebt;

    // poolId => (userAddr => rewardDebt); userAddr is voter
    mapping(uint256 => mapping(address => uint256)) public voterRewardDebt;

    // poolId => CreatorRewardDebt
    mapping(uint256 => uint256) public CreatorRewardDebt;

    // poolId => totalIpistrAmount
    mapping(uint256 => uint256) public totalIpistrAmount;

    mapping(uint256 => uint256) public totalTradingFees;

    /// @notice Records of poolInfo indexed by id
    mapping(uint256 => PoolInfo) public poolInfoMap;

    mapping(uint256 => mapping(address => RewardDebtInfo)) public rewardDebtInfoMap;
}
