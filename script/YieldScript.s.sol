// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "../lib/forge-std/src/Script.sol";
import {YieldFarmingPool} from "../src/YieldFarmingPool.sol";
import {MockToken} from "../src/MockToken.sol";

contract YieldScript is Script {

    YieldFarmingPool public yieldFarmingPool;
    MockToken public rewardToken;
    MockToken public stakingToken1;
    MockToken public stakingToken2;
    
    address public s_owner = makeAddr("owner");
    
    uint256 public constant INITIAL_SUPPLY = 1_000_000;

    // function setUp() public {}

    function run() public returns(
        address, MockToken, MockToken, MockToken, YieldFarmingPool
    ) {
        vm.startBroadcast();

        rewardToken = new MockToken("REWARD", "RWD", s_owner, INITIAL_SUPPLY);

        stakingToken1 = new MockToken("TOKEN1", "STK1", s_owner, INITIAL_SUPPLY);

        stakingToken2 = new MockToken("TOKEN2", "STK2", s_owner, INITIAL_SUPPLY);

        yieldFarmingPool = new YieldFarmingPool(s_owner, address(rewardToken));

        vm.stopBroadcast();

        return (rewardToken.owner(), rewardToken, stakingToken1, stakingToken2, yieldFarmingPool);
    }
}
