// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "../lib/forge-std/src/Test.sol";
import {YieldFarmingPool} from "../src/YieldFarmingPool.sol";
import {YieldScript} from "../script/YieldScript.s.sol";
import {MockToken} from "../src/MockToken.sol";
import {AbiEncoder} from "../src/AbiLibrary.sol";

contract YieldTest is Test {
    YieldFarmingPool public yieldFarmingPool;
    MockToken public rewardToken;
    MockToken public stakingToken1;
    MockToken public stakingToken2;

    address owner;
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    bytes32 public poolId1;
    bytes32 public poolId2;
    
    uint256 public constant TOKEN_AMOUNT_TRANSFER = 10_000 * 10**18;
    uint256 public constant REWARD_TOKENS_SUPPLY = 500_000 * 10**18;
    uint256 public constant REWARD_RATE = 1 * 10**16; // 0.01 tokens per second

    // Events to test emissions
    event PoolCreated(bytes32 indexed poolId, address indexed token, uint256 rewardRate);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Withdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);
    event PoolUpdated(bytes32 indexed poolId, uint256 newRewardRate);

    function setUp() public {
        YieldScript deployer = new YieldScript();
        (owner, rewardToken, stakingToken1, stakingToken2, yieldFarmingPool) = deployer.run();

        vm.startPrank(owner);
        stakingToken1.transfer(user1, TOKEN_AMOUNT_TRANSFER);
        stakingToken1.transfer(user2, TOKEN_AMOUNT_TRANSFER);
        stakingToken2.transfer(user1, TOKEN_AMOUNT_TRANSFER);
        stakingToken2.transfer(user3, TOKEN_AMOUNT_TRANSFER);

        rewardToken.transfer(address(yieldFarmingPool), REWARD_TOKENS_SUPPLY);
        vm.stopPrank();

        vm.startPrank(owner);
        poolId1 = yieldFarmingPool.createPool(address(stakingToken1), REWARD_RATE);
        poolId2 = yieldFarmingPool.createPool(address(stakingToken2), REWARD_RATE * 2);
        vm.stopPrank();

        vm.startPrank(user1);
        stakingToken1.approve(address(yieldFarmingPool), type(uint256).max);
        stakingToken2.approve(address(yieldFarmingPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user2);
        stakingToken1.approve(address(yieldFarmingPool), type(uint256).max);
        vm.stopPrank();
        
        vm.startPrank(user3);
        stakingToken2.approve(address(yieldFarmingPool), type(uint256).max);
        vm.stopPrank();
    }

    // ==========================================
    // 1. CONSTRUCTOR & SETUP TESTS
    // ==========================================

    function test_Constructor_RevertIf_ZeroRewardToken() public {
        vm.expectRevert("Invalid reward token");
        new YieldFarmingPool(owner, address(0));
    }

    function testCreatePool() public view {
        (address token1, uint256 totalStaked1, uint256 rewardRate1, , , bool isActive1) = yieldFarmingPool.s_pools(poolId1);
        (address token2, uint256 totalStaked2, uint256 rewardRate2, , , bool isActive2) = yieldFarmingPool.s_pools(poolId2);
        
        assertTrue(isActive1);
        assertTrue(isActive2);
        assertEq(token1, address(stakingToken1));
        assertEq(token2, address(stakingToken2));
        assertEq(rewardRate1, REWARD_RATE);
        assertEq(rewardRate2, REWARD_RATE * 2);
        assertEq(totalStaked1, 0);
        assertEq(totalStaked2, 0);
    }

    // ==========================================
    // 2. CREATE POOL TESTS
    // ==========================================

    function test_CreatePool_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        yieldFarmingPool.createPool(address(stakingToken1), REWARD_RATE);
    }

    function test_CreatePool_RevertIf_ZeroTokenAddress() public {
        vm.prank(owner);
        vm.expectRevert("Invalid token address");
        yieldFarmingPool.createPool(address(0), REWARD_RATE);
    }

    function test_CreatePool_RevertIf_ZeroRewardRate() public {
        vm.prank(owner);
        vm.expectRevert("Reward rate must be positive");
        yieldFarmingPool.createPool(address(stakingToken1), 0);
    }

    function test_CreatePool_RevertIf_PoolAlreadyExists() public {
        vm.startPrank(owner);
        // Since encodeCreatePoolId uses timestamp and chainid, calling twice in same timestamp produces same ID
        vm.expectRevert("Pool already exists");
        yieldFarmingPool.createPool(address(stakingToken1), REWARD_RATE);
        vm.stopPrank();
    }

    // ==========================================
    // 3. STAKE TESTS
    // ==========================================

    function test_Stake_RevertIf_PoolNotActive() public {
        vm.prank(user1);
        vm.expectRevert("Pool is not active");
        yieldFarmingPool.stake(bytes32("fake_pool_id"), 100);
    }

    function test_Stake_RevertIf_ZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Amount must be positive");
        yieldFarmingPool.stake(poolId1, 0);
    }

    function test_Stake_Success() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Staked(poolId1, user1, stakeAmount);
        yieldFarmingPool.stake(poolId1, stakeAmount);

        (uint256 amount, uint256 rewardDebt, ) = yieldFarmingPool.s_userInfo(poolId1, user1);
        assertEq(amount, stakeAmount);
        assertEq(rewardDebt, 0);

        (, uint256 totalStaked, , , , ) = yieldFarmingPool.s_pools(poolId1);
        assertEq(totalStaked, stakeAmount);
    }

    function test_Stake_SecondTime_ClaimsPendingRewards() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);

        // Fast forward 100 seconds
        vm.warp(block.timestamp + 100);

        uint256 expectedReward = 100 * REWARD_RATE;
        uint256 initialRewardBalance = rewardToken.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit RewardClaimed(poolId1, user1, expectedReward);
        
        // Stake again to trigger auto-claim branch
        yieldFarmingPool.stake(poolId1, stakeAmount);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(user1) - initialRewardBalance, expectedReward);
    }
    
    // ==========================================
    // 4. WITHDRAW TESTS
    // ==========================================

    function test_Withdraw_RevertIf_InsufficientStakedAmount() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);

        vm.expectRevert("Insufficient staked amount");
        yieldFarmingPool.withdraw(poolId1, stakeAmount + 1);
        vm.stopPrank();
    }

    function test_Withdraw_Success_WithRewards() public {
        uint256 stakeAmount = 1000 * 10**18;
        uint256 withdrawAmount = 500 * 10**18; // Partial withdraw due to contract logic
        
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);

        vm.warp(block.timestamp + 100);
        uint256 expectedReward = 100 * REWARD_RATE;

        vm.expectEmit(true, true, false, true);
        emit RewardClaimed(poolId1, user1, expectedReward);
        
        vm.expectEmit(true, true, false, true);
        emit Withdrawn(poolId1, user1, withdrawAmount);

        yieldFarmingPool.withdraw(poolId1, withdrawAmount);
        vm.stopPrank();

        (uint256 remainingAmount, , ) = yieldFarmingPool.s_userInfo(poolId1, user1);
        assertEq(remainingAmount, stakeAmount - withdrawAmount);
        assertEq(rewardToken.balanceOf(user1), expectedReward);
    }

    // ==========================================
    // 5. CLAIM REWARDS TESTS
    // ==========================================

    function test_ClaimRewards_RevertIf_NoRewardsToClaim() public {
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, 1000 * 10**18);
        
        vm.expectRevert("No rewards to claim");
        yieldFarmingPool.claimRewards(poolId1);
        vm.stopPrank();
    }

    function test_ClaimRewards_Success() public {
        uint256 stakeAmount = 1000 * 10**18;
        
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, stakeAmount);

        vm.warp(block.timestamp + 200);
        uint256 expectedReward = 200 * REWARD_RATE;

        vm.expectEmit(true, true, false, true);
        emit RewardClaimed(poolId1, user1, expectedReward);

        yieldFarmingPool.claimRewards(poolId1);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(user1), expectedReward);
    }

    // ==========================================
    // 6. UPDATE POOL REWARD RATE TESTS
    // ==========================================

    function test_UpdatePoolRewardRate_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        yieldFarmingPool.updatePoolRewardRate(poolId1, REWARD_RATE * 5);
    }

    function test_UpdatePoolRewardRate_RevertIf_PoolNotActive() public {
        vm.prank(owner);
        vm.expectRevert("Pool is not active");
        yieldFarmingPool.updatePoolRewardRate(bytes32("fake_pool"), REWARD_RATE * 5);
    }

    function test_UpdatePoolRewardRate_Success() public {
        uint256 newRate = REWARD_RATE * 10;
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit PoolUpdated(poolId1, newRate);
        yieldFarmingPool.updatePoolRewardRate(poolId1, newRate);

        (, , uint256 updatedRate, , , ) = yieldFarmingPool.s_pools(poolId1);
        assertEq(updatedRate, newRate);
    }

    // ==========================================
    // 7. VIEW & HELPER FUNCTIONS TESTS
    // ==========================================

    function test_GetPoolEncodedData() public view {
        bytes memory data = yieldFarmingPool.getPoolEncodedData(poolId1);
        assertTrue(data.length > 0);
    }

    function test_GetUserHash() public view {
        bytes32 hash = yieldFarmingPool.getUserHash(poolId1, user1);
        assertTrue(hash != bytes32(0));
    }

    function test_GetActivePools_And_Count() public view {
        assertEq(yieldFarmingPool.getActivePoolsCount(), 2);
        bytes32[] memory pools = yieldFarmingPool.getActivePools();
        assertEq(pools.length, 2);
        assertEq(pools[0], poolId1);
        assertEq(pools[1], poolId2);
    }

    // ==========================================
    // 8. EMERGENCY WITHDRAW TESTS
    // ==========================================

    function test_EmergencyWithdraw_RevertIf_NotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        yieldFarmingPool.emergencyWithdraw(address(rewardToken), 100);
    }

    function test_EmergencyWithdraw_Success() public {
        uint256 initialOwnerBalance = rewardToken.balanceOf(owner);
        uint256 withdrawAmount = 10_000 * 10**18;

        vm.prank(owner);
        yieldFarmingPool.emergencyWithdraw(address(rewardToken), withdrawAmount);

        assertEq(rewardToken.balanceOf(owner) - initialOwnerBalance, withdrawAmount);
    }

    // ==========================================
    // 9. EDGE CASES & INTERNAL BRANCH COVERAGE
    // ==========================================

    function test_SafeRewardsTransfer_WhenAmountExceedsBalance() public {
        // Stake tokens
        vm.startPrank(user1);
        yieldFarmingPool.stake(poolId1, 1000 * 10**18);
        vm.stopPrank();

        // Drain almost all reward tokens using emergency withdraw to leave only 50 tokens
        uint256 currentRewardBalance = rewardToken.balanceOf(address(yieldFarmingPool));
        uint256 leftOver = 50 * 10**18;
        vm.prank(owner);
        yieldFarmingPool.emergencyWithdraw(address(rewardToken), currentRewardBalance - leftOver);

        // Fast forward time so pending rewards heavily exceed the remaining 50 tokens
        vm.warp(block.timestamp + 1_000_000);

        // Claim rewards: should hit the `if (amount > rewardBalance)` branch and transfer only what is left
        vm.prank(user1);
        yieldFarmingPool.claimRewards(poolId1);

        assertEq(rewardToken.balanceOf(user1), leftOver);
        assertEq(rewardToken.balanceOf(address(yieldFarmingPool)), 0);
    }

    // ==========================================
    // 10. MOCK TOKEN COVERAGE
    // ==========================================

    function test_MockToken_Mint_And_Burn() public {
        vm.prank(owner);
        stakingToken1.mint(user1, 500 * 10**18);
        
        vm.prank(user2);
        vm.expectRevert();
        stakingToken1.mint(user2, 100);

        vm.prank(user1);
        stakingToken1.burn(100 * 10**18);
    }

    // ==========================================
    // 11. ABI ENCODER LIBRARY COVERAGE
    // ==========================================

    function test_AbiEncoder_AllFunctions() public view {
        AbiEncoder.createPoolIdentifier(address(stakingToken1), address(stakingToken2), 3000);
        AbiEncoder.createPoolIdentifier(address(stakingToken2), address(stakingToken1), 3000); // Test sorting branch
        
        AbiEncoder.encodeTradingPosition(user1, address(stakingToken1), address(stakingToken2), 100, 90, block.timestamp);
        
        address[] memory path = new address[](2);
        path[0] = address(stakingToken1);
        path[1] = address(stakingToken2);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100;
        amounts[1] = 200;
        AbiEncoder.encodeSwapData(path, amounts, block.timestamp);

        AbiEncoder.encodeLimitOrder(user1, user2, address(stakingToken1), address(stakingToken2), 100, 200, 1);
        AbiEncoder.encodeYieldPosition(user1, poolId1, 1000, block.timestamp);
        AbiEncoder.encodeFlashLoanData(address(stakingToken1), 1000, "");
        AbiEncoder.encodeStakingPoolConfig(address(stakingToken1), 100, 3600, 50);
        AbiEncoder.encodeCreatePoolId(address(stakingToken1), 100);
        AbiEncoder.poolEncodedData(address(stakingToken1), 1000, 100, block.timestamp, 1e18, true);
        AbiEncoder.encodeUserHash(poolId1, user1);

        bytes32[] memory poolIds = new bytes32[](2);
        poolIds[0] = poolId1;
        poolIds[1] = poolId2;
        AbiEncoder.createUserMultiPullHash(user1, poolIds);

        AbiEncoder.encodeYieldStrategy("Strategy 1", path, amounts);
        AbiEncoder.encodeCrossChainBridgeData(1, 2, address(stakingToken1), 1000, user2);
        AbiEncoder.createDefiTransactionId("SWAP", user1, block.timestamp, 1);
        AbiEncoder.encodeStopLossOrder(user1, address(stakingToken1), 100, 50, 45);
        AbiEncoder.encodeTakeProfitOrder(user1, address(stakingToken1), 100, 150);
        AbiEncoder.encodeTrailingStopOrder(user1, address(stakingToken1), 100, 5, 110);
    }

    function test_AbiEncoder_Reverts() public {
        address[] memory path = new address[](2);
        uint256[] memory amounts = new uint256[](1); // Mismatched length

        vm.expectRevert("Array length mismatch");
        AbiEncoder.encodeSwapData(path, amounts, block.timestamp);

        vm.expectRevert("Arrays length mismatch");
        AbiEncoder.encodeYieldStrategy("Strategy 1", path, amounts);
    }
}