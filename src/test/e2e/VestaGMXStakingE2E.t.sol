// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import { BaseTest, console } from "../common/base/BaseTest.t.sol";
import "../common/mock/MockERC20.sol";

import "../../main/interface/IGMXRewardRouterV2.sol";
import "../../main/interface/IGMXRewardTracker.sol";
import { VestaGMXStaking } from "../../main/VestaGMXStaking.sol";

contract VestaGMXStakingE2E is BaseTest {
	MockERC20 private GMX = MockERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);

	address private GMXRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;

	IGMXRewardTracker private rewardGMX =
		IGMXRewardTracker(0xd2D1162512F927a7e282Ef43a362659E4F2a728F);

	address private stakedGmxTracker = 0x908C4D94D34924765f1eDc22A1DD098397c59dD4;

	address private HOLDER_GMX = 0x908C4D94D34924765f1eDc22A1DD098397c59dD4;

	address private owner = accounts.PUBLIC_KEYS(0);
	address private operator = accounts.PUBLIC_KEYS(1);
	address private userA = address(0x001);
	address private userB = address(0x002);
	address private userC = address(0x003);
	address private treasury = address(0x004);

	VestaGMXStaking private underTest;

	function setUp() public {
		vm.prank(HOLDER_GMX);
		GMX.transfer(operator, 100_000 ether);

		underTest = new VestaGMXStaking();
		vm.startPrank(owner);
		{
			underTest.setUp(
				treasury,
				address(GMX),
				GMXRouter,
				stakedGmxTracker,
				address(rewardGMX)
			);

			vm.etch(operator, "Operator");
			underTest.setOperator(operator, true);
		}
		vm.stopPrank();

		vm.prank(operator);
		GMX.approve(address(underTest), type(uint256).max);
	}

	function test_stake_onBehalfOfUserA_thenWait() public prankAs(operator) {
		uint256 staking = 10_000 ether;

		underTest.stake(userA, staking);
		underTest.stake(userB, staking / 2);

		vm.warp(block.timestamp + 30 days);

		underTest.unstake(userA, staking);
		underTest.unstake(userB, staking / 2);

		assertTrue(userA.balance != 0);
		assertTrue(userB.balance != 0);
		assertTrue(treasury.balance != 0);
		assertTrue(address(underTest).balance <= 1);
	}
}
