// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import { BaseTest, console } from "../common/base/BaseTest.t.sol";
import "../common/mock/MockERC20.sol";

import "../../main/interface/IGMXRewardRouterV2.sol";
import "../../main/interface/IGMXRewardTracker.sol";
import { VestaGLPStaking } from "../../main/VestaGLPStaking.sol";

interface Minter {
	function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp) external payable;
}

contract VestaGLPStakingE2E is BaseTest {
	Minter private MINTER = Minter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
	MockERC20 private FEE_GLP = MockERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903);
	MockERC20 private STAKED_GLP =
		MockERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE);

	address private GMXRouter = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
	address private feeGlpTracker = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
	address private priceFeed = 0xd218Ba424A6166e37A454F8eCe2bf8eB2264eCcA;

	address private owner = accounts.PUBLIC_KEYS(0);
	address private operator = accounts.PUBLIC_KEYS(1);
	address private userA = address(0x001);
	address private userB = address(0x002);
	address private userC = address(0x003);
	address private treasury = address(0x004);

	VestaGLPStaking private underTest;

	function setUp() public {
		underTest = new VestaGLPStaking();
		_mockOperator();

		vm.startPrank(owner);
		{
			underTest.setUp(treasury, address(STAKED_GLP), GMXRouter, feeGlpTracker);
			underTest.setOperator(operator, true);
			underTest.setPriceFeed(priceFeed);
		}
		vm.stopPrank();
	}

	function _mockOperator() internal {
		vm.startPrank(operator);
		{
			vm.deal(operator, 200 ether);
			MINTER.mintAndStakeGlpETH{ value: 200 ether }(0 ether, 100_000 ether);

			//remove the GLP locks
			vm.warp(block.timestamp + 16 minutes);
			vm.etch(operator, address(this).code);

			STAKED_GLP.approve(address(underTest), type(uint256).max);

			assertGt(FEE_GLP.balanceOf(operator), 0);
		}
		vm.stopPrank();
	}

	function test_getAPY() public prankAs(operator) {
		underTest.treasuryFee();
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

