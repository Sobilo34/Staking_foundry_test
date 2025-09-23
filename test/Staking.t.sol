// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import  "forge-std/Test.sol";
import {StakingRewards, IERC20} from "src/Staking.sol";
import {MockERC20} from "test/MockErc20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address bilal = makeAddr("bilal");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(address(staking.stakingToken()), address(stakingToken), "Wrong staking token address");
        assertEq(address(staking.rewardsToken()), address(rewardToken), "Wrong reward token address");

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(staking.totalSupply(), _totalSupplyBeforeStaking + 5e18, "totalsupply didnt update correctly");
    }

    function  test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), userStakebefore - 2e18, "Balance didnt update correctly");
        assertLt(staking.totalSupply(), totalSupplyBefore, "total supply didnt update correctly");

    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward 
        vm.warp(block.timestamp + 200);
        // notify rewards 
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner); 
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        
        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);
    
        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether)/uint256(1 weeks));
        assertEq(staking.finishAt(), uint256(block.timestamp) + uint256(1 weeks));
        assertEq(staking.updatedAt(), block.timestamp);
    
        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
    
    }

    function test_earned_function() public {
        // Set up rewards duration first
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        
        // Add rewards to the contract
        deal(address(rewardToken), owner, 1000 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 1000 ether);
        staking.notifyRewardAmount(1000 ether);
        vm.stopPrank();

        // User stakes some tokens
        deal(address(stakingToken), bob, 100e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(50e18);
        
        // Initially earned should be 0
        assertEq(staking.earned(bob), 0, "Initial earned should be 0");
        
        // Fast forward time to accrue rewards
        vm.warp(block.timestamp + 1 days);
        
        // Check that user has earned some rewards
        uint256 earnedAmount = staking.earned(bob);
        assertTrue(earnedAmount > 0, "User should have earned rewards");
        vm.stopPrank();
    }

    function test_getReward_function() public {
        // Set up rewards system
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        
        deal(address(rewardToken), owner, 1000 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 1000 ether);
        staking.notifyRewardAmount(1000 ether);
        vm.stopPrank();

        // User stakes tokens
        deal(address(stakingToken), bob, 100e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(50e18);
        
        // Fast forward time
        vm.warp(block.timestamp + 1 days);
        
        uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(bob);
        
        // Claim rewards
        staking.getReward();
        
        // Check rewards were claimed
        assertEq(staking.rewards(bob), 0, "Rewards should be reset to 0");
        assertGt(rewardToken.balanceOf(bob), rewardTokenBalanceBefore, "User should receive reward tokens");
        vm.stopPrank();
    }

    function test_getReward_when_no_rewards() public {
        // User with no stake tries to get rewards
        vm.prank(bob);
        staking.getReward(); // Should not revert, just do nothing
        assertEq(staking.rewards(bob), 0, "Rewards should remain 0");
    }

    function test_lastTimeRewardApplicable() public {
        // Test when no rewards are set
        uint256 initialTime = staking.lastTimeRewardApplicable();
        assertEq(initialTime, 0, "Should return 0 when finishAt is 0");
        
        // Set up rewards
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        
        deal(address(rewardToken), owner, 1000 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 1000 ether);
        staking.notifyRewardAmount(1000 ether);
        vm.stopPrank();
        
        // Should return current timestamp when rewards are active
        assertEq(staking.lastTimeRewardApplicable(), block.timestamp, "Should return current time when rewards active");
        
        // Fast forward past reward finish time
        vm.warp(block.timestamp + 2 weeks);
        assertEq(staking.lastTimeRewardApplicable(), staking.finishAt(), "Should return finishAt when past finish time");
    }

    function test_rewardPerToken_edge_cases() public {
        // Test when totalSupply is 0
        uint256 rewardPerToken = staking.rewardPerToken();
        assertEq(rewardPerToken, 0, "Should return stored value when totalSupply is 0");
        
        // Set up rewards
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        
        deal(address(rewardToken), owner, 1000 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 1000 ether);
        staking.notifyRewardAmount(1000 ether);
        vm.stopPrank();
        
        // Still should return stored value when no stakers
        rewardPerToken = staking.rewardPerToken();
        assertEq(rewardPerToken, 0, "Should still return stored value when no stakers");
        
        // Add a staker
        deal(address(stakingToken), bob, 100e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(50e18);
        vm.stopPrank();
        
        // Fast forward time
        vm.warp(block.timestamp + 1 days);
        
        // Now should calculate rewards
        uint256 newRewardPerToken = staking.rewardPerToken();
        assertTrue(newRewardPerToken > 0, "Should calculate rewards when stakers present");
    }

    function test_withdraw_more_than_balance() public {
        // First stake some tokens
        deal(address(stakingToken), bob, 100e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(50e18);
        
        // Try to withdraw more than staked
        vm.expectRevert(); // This will trigger an underflow revert
        staking.withdraw(100e18);
        vm.stopPrank();
    }

    function test_notifyRewardAmount_ongoing_rewards() public {
        // Set up initial rewards
        vm.prank(owner);
        staking.setRewardsDuration(2 weeks);
        
        deal(address(rewardToken), owner, 2000 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 1000 ether);
        staking.notifyRewardAmount(1000 ether);
        
        uint256 initialFinishAt = staking.finishAt();
        
        // Fast forward but not past finish time
        vm.warp(block.timestamp + 1 weeks);
        
        // Add more rewards while ongoing
        IERC20(address(rewardToken)).transfer(address(staking), 1000 ether);
        staking.notifyRewardAmount(500 ether);
        
        // Should extend rewards and may adjust rate (depending on remaining rewards)
        assertTrue(staking.finishAt() > initialFinishAt, "Finish time should be extended");
        // The reward rate calculation includes remaining rewards, so it may or may not change
        // Let's just verify the state is consistent
        assertTrue(staking.rewardRate() > 0, "Reward rate should be positive");
        assertTrue(staking.finishAt() > block.timestamp, "Finish time should be in future");
        vm.stopPrank();
    }

    function test_multiple_users_staking_and_rewards() public {
        // Set up rewards
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        
        deal(address(rewardToken), owner, 1000 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 1000 ether);
        staking.notifyRewardAmount(1000 ether);
        vm.stopPrank();
        
        // User 1 stakes
        deal(address(stakingToken), bob, 100e18);
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(50e18);
        vm.stopPrank();
        
        // Fast forward
        vm.warp(block.timestamp + 1 days);
        
        // User 2 stakes
        deal(address(stakingToken), bilal, 100e18);
        vm.startPrank(bilal);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        staking.stake(30e18);
        vm.stopPrank();
        
        // Fast forward more
        vm.warp(block.timestamp + 1 days);
        
        // Both users should have earned rewards
        assertTrue(staking.earned(bob) > 0, "Bob should have earned rewards");
        assertTrue(staking.earned(bilal) > 0, "Bilal should have earned rewards");
        
        // Bob should have more rewards (staked earlier and more)
        assertTrue(staking.earned(bob) > staking.earned(bilal), "Bob should have more rewards");
        
        // Test getReward for both users
        vm.prank(bob);
        staking.getReward();
        
        vm.prank(bilal);
        staking.getReward();
        
        // Both should have received tokens
        assertTrue(rewardToken.balanceOf(bob) > 0, "Bob should receive reward tokens");
        assertTrue(rewardToken.balanceOf(bilal) > 0, "Bilal should receive reward tokens");
    }

    function test_updateReward_modifier_with_zero_address() public {
        // This tests the updateReward modifier when called with address(0)
        // This happens in notifyRewardAmount function
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        
        deal(address(rewardToken), owner, 1000 ether);
        vm.startPrank(owner);
        IERC20(address(rewardToken)).transfer(address(staking), 1000 ether);
        
        // This will trigger updateReward(address(0))
        staking.notifyRewardAmount(1000 ether);
        
        // Verify state was updated correctly
        assertEq(staking.updatedAt(), block.timestamp, "updatedAt should be current timestamp");
        assertTrue(staking.rewardRate() > 0, "Reward rate should be set");
        vm.stopPrank();
    }


}