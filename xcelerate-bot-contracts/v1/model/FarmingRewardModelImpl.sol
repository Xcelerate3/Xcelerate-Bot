// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../libraries/AllyLibrary.sol";
import "../../interfaces/v1/model/IFarmingRewardModel.sol";
import "../../interfaces/IShorterBone.sol";
import "../../criteria/ChainSchema.sol";
import "../../storage/model/FarmingRewardModelStorage.sol";
import "../../util/BoringMath.sol";

contract FarmingRewardModelImpl is ChainSchema, FarmingRewardModelStorage, IFarmingRewardModel {
    using BoringMath for uint256;
    using SafeToken for ISRC20;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {}

    function harvestByPool(address user) external override returns (uint256 rewards) {
            require(msg.sender == address(farming), "FarmingReward: Caller is not Farming");
        rewards = _harvest(user);
    }

    function harvest(address user) external override returns (uint256 rewards) {
        require(msg.sender == address(farming) || msg.sender == user, "FarmingReward: Caller is neither Farming nor User");
        rewards = _harvest(user);
        farming.harvest(farming.getTokenId(), user);
    }

    function pendingReward(address _user) public view override returns (uint256 unLockRewards_, uint256 rewards_) {
        uint256 userStakedAmount = _getUserStakedAmount(_user);

        if (userStakedAmount == 0 || maxLpSupply == 0 || maxUnlockSpeed == 0) {
            return (0, 0);
        }

        uint256 userLockedAmount = _getLockedBalanceOf(_user);

        if (userLockedAmount > 0) {
            uint256 unlockedSpeed = _getUnlockSpeed(userStakedAmount);
            uint256 estimateEndBlock = (userLockedAmount.div(unlockedSpeed)).add(userLastRewardBlock[_user]);
            if (estimateEndBlock > block.number) {
                unLockRewards_ = (block.number.sub(userLastRewardBlock[_user])).mul(unlockedSpeed);
                return (unLockRewards_, 0);
            } else {
                unLockRewards_ = userLockedAmount;
                uint256 baseSpeed = _getBaseSpeed(userStakedAmount);
                rewards_ = (block.number.sub(estimateEndBlock)).mul(baseSpeed);
                return (unLockRewards_, rewards_);
            }
        }

        uint256 baseSpeed = _getBaseSpeed(userStakedAmount);
        rewards_ = (block.number.sub(userLastRewardBlock[_user])).mul(baseSpeed);
    }

    function getSpeed(address user) external view returns (uint256 speed) {
        uint256 userLockedAmount = _getLockedBalanceOf(user);
        uint256 userStakedAmount = _getUserStakedAmount(user);

        if (userStakedAmount == 0 || maxLpSupply == 0 || maxUnlockSpeed == 0) {
            return 0;
        }

        if (userLockedAmount > 0) {
            speed = _getUnlockSpeed(userStakedAmount);
            uint256 estimateEndBlock = (userLockedAmount.div(speed)).add(userLastRewardBlock[user]);

            if (estimateEndBlock > block.number) {
                return speed;
            }
        }

        speed = _getBaseSpeed(userStakedAmount);
    }

    function setMaxUnlockSpeed(uint256 _maxUnlockSpeed) external isManager {
        maxUnlockSpeed = _maxUnlockSpeed;
    }

    function setMaxLpSupply(uint256 _maxLpSupply) external isManager {
        maxLpSupply = _maxLpSupply;
    }

    function _getBaseSpeed(uint256 userStakedAmount) internal view returns (uint256 speed) {
        if (userStakedAmount >= maxLpSupply) {
            return maxUnlockSpeed;
        }

        return maxUnlockSpeed.mul(userStakedAmount).div(maxLpSupply);
    }

    function _getUnlockSpeed(uint256 userStakedAmount) internal view returns (uint256 speed) {
        if (userStakedAmount.mul(2 ** 10) < maxLpSupply) {
            return userStakedAmount.mul(2 ** 10).mul(maxUnlockSpeed).div(maxLpSupply).div(10);
        }

        if (userStakedAmount >= maxLpSupply) {
            return maxUnlockSpeed;
        }

        for (uint256 i = 0; i < 10; i++) {
            if (userStakedAmount.mul(2 ** (9 - i)) < maxLpSupply) {
                uint256 _speed = (userStakedAmount.mul(2 ** (10 - i)).sub(maxLpSupply)).mul(maxUnlockSpeed).div(maxLpSupply).div(10);
                speed = speed.add(_speed);
                break;
            }

            speed = speed.add(maxUnlockSpeed.div(10));
        }
    }

    function _getUserStakedAmount(address _user) internal view returns (uint256 userStakedAmount_) {
        userStakedAmount_ = farming.getUserStakedAmount(_user);
    }

    function _getLockedBalanceOf(address account) internal view returns (uint256) {
        return ipistrToken.lockedBalanceOf(account);
    }

    function _harvest(address user) internal returns (uint256 rewards) {
        (uint256 _unLockRewards, uint256 _rewards) = pendingReward(user);
        if (_unLockRewards > 0) {
            ipistrToken.unlockBalance(user, _unLockRewards);
        }

        if (_rewards > 0) {
            shorterBone.mintByAlly(AllyLibrary.FARMING_REWARD, user, _rewards);
        }

        rewards = _unLockRewards.add(_rewards);
        userLastRewardBlock[user] = block.number;
    }

    function setFarming(address newFarming) external isSavior {
        require(newFarming != address(0), "PoolReward: newFarming is zero address");
        farming = IFarming(newFarming);
    }

    function initialize(address _shorterBone, address _farming, address _ipistrToken) external isSavior {
        require(!_initialized, "FarmingReward: Already initialized");
        maxLpSupply = 1e24;
        maxUnlockSpeed = 1e17;
        shorterBone = IShorterBone(_shorterBone);
        farming = IFarming(_farming);
        ipistrToken = IIpistrToken(_ipistrToken);

        _initialized = true;
    }
}
