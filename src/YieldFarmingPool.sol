// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { IERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import { AbiEncoder } from "./AbiLibrary.sol";

/**
 * @title Yield Farming Pool
 * @author Carlos Gutiérrez
 * @notice Yield farming contract demonstrating the use of abi.encodePacked to encode pool
 * parameters and calculate unique identifiers.
 */
contract YieldFarmingPool is ReentrancyGuard, Ownable {

    using SafeERC20 for IERC20;

    struct Pool {
        address token;
        uint256 totalStaked;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        bool isActive;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastClaimTime;
    }

    IERC20 public s_rewardToken;

    // Mapping of pools by their unique identifier
    mapping(bytes32 poolId => Pool pool) public s_pools;

    // Mapping of user information by pool and address
    mapping(bytes32 => mapping(address => UserInfo)) public s_userInfo;

    // List of all active pools
    bytes32[] public s_activePools;

    // Events
    event PoolCreated(bytes32 indexed poolId, address indexed token, uint256 rewardRate);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Withdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);
    event PoolUpdated(bytes32 indexed poolId, uint256 newRewardRate);
    
    constructor(address _owner, address _rewardToken) Ownable(_owner) {
        require(_rewardToken != address(0), "Invalid reward token");
        s_rewardToken = IERC20(_rewardToken);
    }

    /**
     * @dev Creates a new yield farming pool
     * @param token address of the token to stake
     * @param rewardRate reward rate per second
     * @return poolId Unique pool identifier
     */
    function createPool(address token, uint256 rewardRate) external onlyOwner returns(bytes32 poolId) {
        require(token != address(0), "Invalid token address");
        require(rewardRate > 0, "Reward rate must be positive");
        poolId = AbiEncoder.encodeCreatePoolId(token, rewardRate);

        require(s_pools[poolId].token ==address(0), "Pool already exists");

        s_pools[poolId] = Pool({
            token: token,
            totalStaked: 0,
            rewardRate: rewardRate,
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            isActive: true
        });

        s_activePools.push(poolId);

        emit PoolCreated(poolId, token, rewardRate);
    }

    /**
     * @dev Stake tokens in a specific pool
     * @param poolId Pool identifier
     * @param amount Amount of tokens to stake
     */
    function stake(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = s_pools[poolId];
        require(pool.isActive, "Pool is not active");
        require(amount > 0, "Amount must be positive");

        _updatePool(poolId);

        UserInfo storage user = s_userInfo[poolId][msg.sender];

        if (user.amount > 0) {
            uint256 pending = _calculatePendingReward(poolId, msg.sender);
            if (pending > 0) {
                _safeRewardsTransfer(msg.sender, pending);
                emit RewardClaimed(poolId, msg.sender, pending);
            }
        }

        IERC20(pool.token).safeTransferFrom(msg.sender, address(this), amount);

        user.amount += amount;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18;
        user.lastClaimTime = block.timestamp;

        pool.totalStaked += amount;

        emit Staked(poolId, msg.sender, amount);

    }

    /**
     * @dev Withdraw staked tokens from a pool
     * @param poolId Pool identifier
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(bytes32 poolId, uint256 amount) external nonReentrant {
        Pool storage pool = s_pools[poolId];
        UserInfo storage user = s_userInfo[poolId][msg.sender];

        require(user.amount >= amount, "Insufficient staked amount");

        _updatePool(poolId);

        uint256 pending = _calculatePendingReward(poolId, msg.sender);
        if (pending > 0) {
            _safeRewardsTransfer(msg.sender, pending);
            emit RewardClaimed(poolId, msg.sender, pending);
        }

        user.amount -= amount;
        user.rewardDebt = user.amount * pool.rewardPerTokenStored / 1e18;

        pool.totalStaked -= amount;

        IERC20(pool.token).safeTransfer(msg.sender, amount);

        emit Withdrawn(poolId, msg.sender, amount);

    }

    /**
     * @dev Claim pending rewards
     * @param poolId Pool identifier
     */
    function claimRewards(bytes32 poolId) external nonReentrant {

        _updatePool(poolId);

        uint256 pending = _calculatePendingReward(poolId, msg.sender);
        require(pending > 0, "No rewards to claim");
        
        UserInfo storage user = s_userInfo[poolId][msg.sender];

        user.rewardDebt = user.amount * s_pools[poolId].rewardPerTokenStored / 1e18;
        user.lastClaimTime = block.timestamp;

        _safeRewardsTransfer(msg.sender, pending);

        emit RewardClaimed(poolId, msg.sender, pending);

    }

    /**
     * @dev Update the reward rate of a pool
     * @param poolId Pool identifier
     * @param newRewardRate New reward rate for a pool
     */
    function updatePoolRewardRate(bytes32 poolId, uint256 newRewardRate) external onlyOwner {

        Pool storage pool = s_pools[poolId];
        require(pool.isActive, "Pool is not active");

        _updatePool(poolId);
        pool.rewardRate = newRewardRate;

        emit PoolUpdated(poolId, newRewardRate);

    }

    /**
     * @dev Encoded Pool Information for external use
     * @param poolId Pool identifier
     * @return encodedData Encoded Pool Data
     */
    function getPoolEncodedData(bytes32 poolId) external view returns(bytes memory encodedData) {
        Pool storage pool = s_pools[poolId];
        encodedData = AbiEncoder.poolEncodedData(
            pool.token,
            pool.totalStaked,
            pool.rewardRate,
            pool.lastUpdateTime,
            pool.rewardPerTokenStored,
            pool.isActive
        );
    }

    /**
     * @dev Creates a unique hash for a user in a specific pool
     * @param poolId Pool identifier
     * @param user User address
     * @return userHash Unique user hash
     */
    function getUserHash(bytes32 poolId, address user) external pure returns(bytes32 userHash) {
        userHash = AbiEncoder.encodeUserHash(poolId, user);
    }

    /**
     * @dev Get the total number of active pools
     * @return Number of active pools
     */
    function getActivePoolsCount() external view returns(uint256) {
        return s_activePools.length;
    }

    /**
     * @dev Get all active pools
     * @return Array with the identifiers of the active pools
     */
    function getActivePools() external view returns(bytes32[] memory) {
        return s_activePools;
    }

    /**
     * @dev Emergency function to withdraw tokens
     * @param token Address token to withdraw
     * @param amount Amount of tokens to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev Update the pool state
     * @param poolId Pool identifier
     */
    function _updatePool(bytes32 poolId) internal {
        Pool storage pool = s_pools[poolId];

        if (pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
            uint256 rewards = timeElapsed * pool.rewardRate;
            pool.rewardPerTokenStored = rewards * 1e18 / pool.totalStaked;
        }

        pool.lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Safely transfer rewards
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function _safeRewardsTransfer(address to, uint256 amount) internal {
        uint256 rewardBalance = s_rewardToken.balanceOf(address(this));
        if (amount > rewardBalance) {
            amount = rewardBalance;
        }

        if (amount > 0) {
            s_rewardToken.safeTransfer(to, amount);
        }
    }

    /**
     * @dev Calculate the pending rewards of a user
     * @param poolId Pool identifier
     * @param user User address
     */
    function _calculatePendingReward(bytes32 poolId, address user) internal view returns(uint256) {
        Pool storage pool = s_pools[poolId];
        UserInfo storage userInfoData = s_userInfo[poolId][user];

        uint256 rewardPerTokenStored = pool.rewardPerTokenStored;

        if (pool.totalStaked > 0) {
            uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
            uint256 rewards = timeElapsed * pool.rewardRate;
            rewardPerTokenStored += rewards * 1e18 / pool.totalStaked;
        }

        return userInfoData.amount * rewardPerTokenStored / 1e18 - userInfoData.rewardDebt;

    }

}
