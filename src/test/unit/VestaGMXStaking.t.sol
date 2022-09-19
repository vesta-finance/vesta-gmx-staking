// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "./BaseGMXProtocol.t.sol";
import "../common/mock/MockERC20.sol";
import { FullMath } from "../../main/lib/FullMath.sol";
import { VestaGMXStaking } from "../../main/VestaGMXStaking.sol";

contract VestaGMXStakingTest is BaseGMXProtocol {
	address private owner = accounts.PUBLIC_KEYS(0);
	address private operator = accounts.PUBLIC_KEYS(1);
	address private MOCK_ADDR = address(0x1);
	address private userA = address(0x001);
	address private userB = address(0x002);
	address private userC = address(0x003);
	address private userD = address(0x004);
	address private userE = address(0x005);
	address private treasury = address(0x006);

	address private stakedGmxTracker = address(0x123);
	address private feeGmxTrackerRewards = address(0x345);
	MockERC20 private GMX = new MockERC20("GMX", "GMX", 18);
	ReentrancyAttack private reentrancyAttacker;

	VestaGMXStaking private underTest;

	function setUp() external {
		vm.deal(address(gmxRouter), 100e32);
		GMX.mint(operator, 100_000e18);

		vm.etch(operator, address(this).code);

		underTest = new VestaGMXStaking();
		interfaceUnderTest = IVestaGMXStaking(underTest);

		vm.startPrank(owner);
		{
			underTest.setUp(
				treasury,
				address(GMX),
				address(gmxRouter),
				stakedGmxTracker,
				feeGmxTrackerRewards
			);

			underTest.setOperator(operator, true);
		}
		vm.stopPrank();

		vm.prank(operator);
		GMX.approve(address(underTest), type(uint256).max);

		reentrancyAttacker = new ReentrancyAttack(operator, underTest, vm);
	}

	function test_setUp_whenCalledTwice_thenReverts() external {
		underTest = new VestaGMXStaking();
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR);

		vm.expectRevert(ERROR_ALREADY_INITIALIZED);
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR);
	}

	function test_setUp_withInvalidAddress_thenReverts() external {
		underTest = new VestaGMXStaking();

		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setUp(address(0), MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR);

		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setUp(MOCK_ADDR, address(0), MOCK_ADDR, MOCK_ADDR, MOCK_ADDR);

		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, address(0), MOCK_ADDR, MOCK_ADDR);

		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, address(0), MOCK_ADDR);
		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, address(0));
	}

	function test_setUp_ThenCallerIsOwner() external prankAs(owner) {
		underTest = new VestaGMXStaking();
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR);

		assertEq(underTest.owner(), owner);
	}

	function test_setUp_thenStorageUpdated() external prankAs(owner) {
		underTest = new VestaGMXStaking();
		underTest.setUp(
			treasury,
			address(GMX),
			address(gmxRouter),
			stakedGmxTracker,
			feeGmxTrackerRewards
		);

		assertEq(underTest.vestaTreasury(), treasury);
		assertEq(underTest.gmxToken(), address(GMX));
		assertEq(address(underTest.gmxRewardRouterV2()), address(gmxRouter));
		assertEq(underTest.stakedGmxTracker(), stakedGmxTracker);
		assertEq(address(underTest.feeGmxTrackerRewards()), feeGmxTrackerRewards);
	}

	function test_setUp_thenAllowanceIsSet() external prankAs(owner) {
		underTest = new VestaGMXStaking();
		underTest.setUp(
			treasury,
			address(GMX),
			address(gmxRouter),
			stakedGmxTracker,
			feeGmxTrackerRewards
		);

		assertEq(GMX.allowance(address(underTest), stakedGmxTracker), type(uint256).max);
	}

	function test_stake_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(abi.encodeWithSignature(ERROR_CALLER_NOT_OPERATOR_SIG, userA));
		underTest.stake(address(0x123), 1e18);
	}

	function test_stake_asOperator_givenInvalidAddress_thenReverts()
		external
		prankAs(operator)
	{
		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.stake(address(0), 1e18);
	}

	function test_stake_asOperator_givenZeroAmount_thenReverts()
		external
		prankAs(operator)
	{
		vm.expectRevert(ERROR_ZERO_AMOUNT_PASSED);
		underTest.stake(MOCK_ADDR, 0);
	}

	function test_stake_asOperator_givenValidArgs_thenHandleRewardsCalled()
		external
		prankAs(operator)
	{
		vm.expectCall(address(gmxRouter), GMX_HANDLE_REWARDS_CALL);
		underTest.stake(userA, 1e18);
	}

	function test_stake_asOperator_givenValidArgsAndFirstStaker_thenTransferAndStakeUpdate()
		external
		prankAs(operator)
	{
		uint256 staking = 24e18;

		vm.expectCall(
			address(GMX),
			abi.encodeWithSignature(
				"transferFrom(address,address,uint256)",
				operator,
				address(underTest),
				24e18
			)
		);

		vm.expectCall(
			address(gmxRouter),
			abi.encodeWithSignature("stakeGmx(uint256)", staking)
		);

		underTest.stake(userA, 24e18);

		assertEq(underTest.getVaultStake(userA), staking);
		assertEq(underTest.getVaultOwnerShare(userA), 0);
		assertEq(underTest.totalStaked(), staking);
	}

	function test_stake_asOperator_givenNewStakerAndPendingReward_thenGivesNothingToStaker()
		external
		prankAs(operator)
	{
		gmxRouter.setNextReward(12e18);
		underTest.stake(userA, 1e18);
		assertEq(userA.balance, 0);
	}

	function test_stake_asOperator_givenNoRewardDistributed_thenLastUpdateBalance()
		external
		prankAs(operator)
	{
		gmxRouter.setNextReward(12e18);
		underTest.stake(userA, 1e18);
		assertEq(underTest.lastBalance(), _applyTreasuryFee(12e18));
	}

	function test_stake_asOperator_givenFirstStaker_thenDontUpdateRewardShare()
		external
		prankAs(operator)
	{
		underTest.stake(userA, 1e18);
		assertEq(underTest.rewardShare(), 0);
	}

	function test_stake_asOperator_userStakesTwiceWithPendingRewards_thenGiveRewardsAndUpdateShareRewards()
		external
		prankAs(operator)
	{
		uint256 reward = 3e18;

		underTest.stake(userA, 1e18);
		gmxRouter.setNextReward(reward);
		underTest.stake(userA, 2e18);

		uint256 expectedBalanceTreasury = (reward * underTest.treasuryFee()) / 10_000;
		uint256 expectedBalanceUser = reward - expectedBalanceTreasury;
		uint256 expectedNewRewardShare = ((reward - expectedBalanceTreasury) *
			PRECISION) / 1e18;

		assertEq(userA.balance, expectedBalanceUser);
		assertEq(treasury.balance, expectedBalanceTreasury);
		assertEq(underTest.rewardShare(), expectedNewRewardShare);
	}

	function test_stake_asOperator_givenNotFirstStakerAndNonZeroRewardShare_thenUpdateStakerOriginalShareWithNewRewardShare()
		external
		prankAs(operator)
	{
		uint256 reward = 3e18;

		underTest.stake(userA, 2e18);
		gmxRouter.setNextReward(reward);
		underTest.stake(userB, 4e18);

		uint256 expectedNewRewardShare = (_applyTreasuryFee(reward) * PRECISION) / 2e18;
		uint256 expectedOriginalShare = (4e18 * expectedNewRewardShare) / PRECISION;

		assertEq(underTest.getVaultOwnerShare(userB), expectedOriginalShare);
	}

	function test_stake_givenReentrancyAttacker_thenEmitFailedToSendEth() external {
		uint256 reward = 1e18;
		uint256 expectingReward = reward - ((reward * underTest.treasuryFee()) / BPS);

		vm.deal(address(underTest), 1000e18);

		vm.prank(operator);
		underTest.stake(address(reentrancyAttacker), 100e18);

		gmxRouter.setNextReward(1e18);

		vm.expectEmit(true, true, true, true);
		emit FailedToSendETH(address(reentrancyAttacker), expectingReward);

		vm.prank(operator);
		underTest.stake(address(reentrancyAttacker), 1e18);

		assertEq(address(reentrancyAttacker).balance, 0);
	}

	function test_unstake_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(abi.encodeWithSignature(ERROR_CALLER_NOT_OPERATOR_SIG, userA));
		underTest.unstake(userA, 1e18);
	}

	function test_unstake_asOperator_givenReentrancyAttacker_thenEmitFailedToSendEth()
		external
		prankAs(operator)
	{
		uint256 reward = 1e18;
		uint256 expectingReward = reward - ((reward * underTest.treasuryFee()) / BPS);

		vm.deal(address(underTest), 30e18);
		underTest.stake(address(reentrancyAttacker), 1e18);
		gmxRouter.setNextReward(1e18);

		vm.expectEmit(true, true, true, true);
		emit FailedToSendETH(address(reentrancyAttacker), expectingReward);

		underTest.unstake(address(reentrancyAttacker), 0);
		assertEq(address(reentrancyAttacker).balance, 0);
	}

	function test_unstake_asOperator_givenNonStaker_thenReverts()
		external
		prankAs(operator)
	{
		vm.expectRevert(ERROR_INSUFFICIENT_STAKE_BALANCE);
		underTest.unstake(userA, 1e18);
	}

	function test_unstake_asOperator_givenStaker_thenCallHandleRewards()
		external
		prankAs(operator)
	{
		underTest.stake(userA, 5e18);
		gmxRouter.setNextReward(100e18);

		vm.expectCall(address(gmxRouter), GMX_HANDLE_REWARDS_CALL);
		underTest.unstake(userA, 1e18);
	}

	function test_unstake_asOperator_givenStaker_thenUpdateStakerShare()
		external
		prankAs(operator)
	{
		gmxRouter.setNextReward(10e18);
		underTest.stake(userA, 5e18);

		uint256 lastShare = underTest.getVaultOwnerShare(userA);
		underTest.unstake(userA, 25e17);

		assertEq(lastShare, lastShare / 2);
	}

	function test_unstake_asOperator_givenStaker_thenUpdateStakingAndSendGMX()
		external
		prankAs(operator)
	{
		gmxRouter.setNextReward(10e18);
		underTest.stake(userA, 5e18);
		uint256 balanceBefore = GMX.balanceOf(operator);

		vm.expectCall(
			address(gmxRouter),
			abi.encodeWithSignature("unstakeGmx(uint256)", 25e17)
		);
		underTest.unstake(userA, 25e17);

		assertEq(underTest.getVaultStake(userA), 25e17);
		assertEq(underTest.totalStaked(), 25e17);
		assertEq(GMX.balanceOf(operator) - balanceBefore, 25e17);
	}

	function test_claim_asNonStaker_thenReverts() external prankAs(userA) {
		vm.expectRevert(ERROR_INSUFFICIENT_STAKE_BALANCE);
		underTest.claim();
	}

	function test_claim_asStaker_whenCalledTwice_thenGiveRewardsOnce()
		external
		prankAs(operator)
	{
		uint256 reward = 10e18;

		underTest.stake(userA, 100e18);

		gmxRouter.setNextReward(10e18);

		changePrank(userA);
		underTest.claim();
		underTest.claim();

		assertEq(userA.balance, _applyTreasuryFee(reward));
	}

	function test_claim_asReentrencyAttacker_thenEmitFailedToSendEth() external {
		uint256 reward = 1e18;
		uint256 expectingReward = reward - ((reward * underTest.treasuryFee()) / BPS);

		vm.deal(address(underTest), 1000e18);

		vm.prank(operator);
		underTest.stake(address(reentrancyAttacker), 100e18);

		gmxRouter.setNextReward(1e18);

		vm.expectEmit(true, true, true, true);
		emit FailedToSendETH(address(reentrancyAttacker), expectingReward);

		vm.prank(address(reentrancyAttacker));
		underTest.claim();

		assertEq(address(reentrancyAttacker).balance, 0);
		assertEq(
			underTest.getRecoverableETH(address(reentrancyAttacker)),
			expectingReward
		);
	}

	function test_setOperator_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(NOT_OWNER);
		underTest.setOperator(address(this), true);
	}

	function test_setOperator_asOwner_givenNonContractAddress_thenReverts()
		external
		prankAs(owner)
	{
		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setOperator(address(0x123), true);
	}

	function test_setOperator_asOwner_givenContractAddress_thenSetsAsOperator()
		external
		prankAs(owner)
	{
		underTest.setOperator(address(this), true);

		assertTrue(underTest.isOperator(address(this)));
	}

	function test_setTreasuryFee_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(NOT_OWNER);
		underTest.setTreasuryFee(BPS);
	}

	function test_setTreasuryFee_asOwner_givenInvalidBPS_thenReverts()
		external
		prankAs(owner)
	{
		vm.expectRevert(ERROR_BPS_HIGHER_THAN_100);
		underTest.setTreasuryFee(10_001);
	}

	function test_setTreasuryFee_asOwner_givenValidBPS_thenUpdateBPS()
		external
		prankAs(owner)
	{
		underTest.setTreasuryFee(9_000);
		assertEq(underTest.treasuryFee(), 9_000);
	}

	function test_setTreasury_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(NOT_OWNER);
		underTest.setTreasury(address(0x123));
	}

	function test_setTreasury_asOwner_thenChangesTreasury() external prankAs(owner) {
		underTest.setTreasury(address(0x123));
		assertEq(underTest.vestaTreasury(), address(0x123));
	}

	function test_getVaultStake_givenStaker_thenReturnsSameAmount()
		external
		prankAs(operator)
	{
		underTest.stake(userA, 23e18);
		assertEq(underTest.getVaultStake(userA), 23e18);
	}

	function test_getVaultOwnerShare_givenNotFirstStaker_thenReturnsSameAmount()
		external
		prankAs(operator)
	{
		underTest.stake(userA, 23e18);
		gmxRouter.setNextReward(10e8);

		underTest.stake(userB, 23e18);
		assertTrue(underTest.getVaultOwnerShare(userB) > 0);
	}

	function test_getVaultOwnerClaimable_givenStakerPendingRewards_thenReturnsSameAmount()
		external
		prankAs(operator)
	{
		uint256 reward = 15e15;

		underTest.stake(userA, 30e18);
		gmxRouter.setNextReward(10e15);
		underTest.stake(userB, 30e18);

		vm.mockCall(
			feeGmxTrackerRewards,
			abi.encodeWithSignature("claimable(address)", address(underTest)),
			abi.encode(10e15)
		);

		assertEq(underTest.getVaultOwnerClaimable(userA), _applyTreasuryFee(reward) - 1);
	}

	function test_harvestRewards_asOperator_givenMultipleStakerAtSameTime_thenDistributeCorrectly()
		external
		prankAs(operator)
	{
		UserStake memory stakingUserA = UserStake(0, userA, 125e18);
		UserStake memory stakingUserB = UserStake(1, userB, 33e18);
		UserStake memory stakingUserC = UserStake(2, userC, 33e18);
		UserStake memory stakingUserD = UserStake(3, userD, 535e18);
		UserStake memory stakingUserE = UserStake(4, userE, 5e18);

		ExpectedHarvestResult memory results;
		ExpectedActionHarvest memory actionHarvest;

		actionHarvest = _stakeWithEstimation(0, stakingUserA, actionHarvest);
		actionHarvest = _stakeWithEstimation(0, stakingUserB, actionHarvest);
		actionHarvest = _stakeWithEstimation(0, stakingUserC, actionHarvest);
		actionHarvest = _stakeWithEstimation(0, stakingUserD, actionHarvest);
		actionHarvest = _stakeWithEstimation(0, stakingUserE, actionHarvest);

		//using high number to check accuracy on extreme case
		gmxRouter.setNextReward(5_000_000e18);

		(actionHarvest, results) = _getHarvestReward(
			5_000_000e18,
			stakingUserD,
			actionHarvest,
			results
		);
		underTest.stake(stakingUserD.wallet, 1e18);
		actionHarvest.totalStaked += 1e18;

		(actionHarvest, results) = _getHarvestReward(
			0,
			stakingUserA,
			actionHarvest,
			results
		);
		underTest.stake(stakingUserA.wallet, 1e18);
		actionHarvest.totalStaked += 1e18;

		(actionHarvest, results) = _getHarvestReward(
			0,
			stakingUserB,
			actionHarvest,
			results
		);
		underTest.stake(stakingUserB.wallet, 1e18);
		actionHarvest.totalStaked += 1e18;

		(actionHarvest, results) = _getHarvestReward(
			0,
			stakingUserE,
			actionHarvest,
			results
		);
		underTest.stake(stakingUserE.wallet, 1e18);
		actionHarvest.totalStaked += 1e18;

		(actionHarvest, results) = _getHarvestReward(
			0,
			stakingUserC,
			actionHarvest,
			results
		);
		underTest.stake(stakingUserC.wallet, 1e18);
		actionHarvest.totalStaked += 1e18;

		assertEq(userA.balance, results.toUser[stakingUserA.id]);
		assertEq(userB.balance, results.toUser[stakingUserB.id]);
		assertEq(userC.balance, results.toUser[stakingUserC.id]);
		assertEq(userD.balance, results.toUser[stakingUserD.id]);
		assertEq(userE.balance, results.toUser[stakingUserE.id]);
		assertEq(treasury.balance, results.toTreasury);

		assertGt(results.toUser[stakingUserD.id], results.toUser[stakingUserA.id]);
		assertGt(results.toUser[stakingUserA.id], results.toUser[stakingUserB.id]);
		assertGt(results.toUser[stakingUserA.id], results.toUser[stakingUserC.id]);
		assertEq(results.toUser[stakingUserB.id], results.toUser[stakingUserC.id]);
		assertGt(results.toUser[stakingUserB.id], results.toUser[stakingUserE.id]);
		assertGt(results.toUser[stakingUserC.id], results.toUser[stakingUserE.id]);
	}

	function test_harvestRewards_asOperator_givenMultipleStakerAtDifferentTime_thenDistributeCorrectly()
		external
		prankAs(operator)
	{
		UserStake memory stakingUserA = UserStake(0, userA, 125e18);
		UserStake memory stakingUserB = UserStake(1, userB, 33e18);
		UserStake memory stakingUserC = UserStake(2, userC, 33e18);
		UserStake memory stakingUserD = UserStake(3, userD, 535e18);
		UserStake memory stakingUserE = UserStake(4, userE, 5e18);

		ExpectedHarvestResult memory results;
		ExpectedActionHarvest memory actionHarvest;

		actionHarvest = _stakeWithEstimation(0, stakingUserA, actionHarvest);
		actionHarvest = _stakeWithEstimation(5e10, stakingUserB, actionHarvest);
		actionHarvest = _stakeWithEstimation(7e10, stakingUserC, actionHarvest);
		actionHarvest = _stakeWithEstimation(5e11, stakingUserD, actionHarvest);
		actionHarvest = _stakeWithEstimation(1e12, stakingUserE, actionHarvest);

		gmxRouter.setNextReward(25e12);
		uint256 estimationToTreasury = 25e12 + 5e10 + 7e10 + 5e11 + 1e12;

		(actionHarvest, results) = _getHarvestReward(
			25e12,
			stakingUserD,
			actionHarvest,
			results
		);
		underTest.unstake(userD, 0);

		(actionHarvest, results) = _getHarvestReward(
			0,
			stakingUserA,
			actionHarvest,
			results
		);
		underTest.unstake(userA, 0);

		(actionHarvest, results) = _getHarvestReward(
			0,
			stakingUserB,
			actionHarvest,
			results
		);
		underTest.unstake(userB, 0);

		(actionHarvest, results) = _getHarvestReward(
			0,
			stakingUserE,
			actionHarvest,
			results
		);
		underTest.unstake(userE, 0);

		(actionHarvest, results) = _getHarvestReward(
			0,
			stakingUserC,
			actionHarvest,
			results
		);
		underTest.unstake(userC, 0);

		assertEq(userA.balance, results.toUser[stakingUserA.id]);
		assertEq(userB.balance, results.toUser[stakingUserB.id]);
		assertEq(userC.balance, results.toUser[stakingUserC.id]);
		assertEq(userD.balance, results.toUser[stakingUserD.id]);
		assertEq(userE.balance, results.toUser[stakingUserE.id]);
		assertEq(
			treasury.balance,
			estimationToTreasury - _applyTreasuryFee(estimationToTreasury)
		);

		assertGt(userA.balance, userB.balance);
		assertGt(userB.balance, userC.balance);
		assertGt(userD.balance, userC.balance);
		assertGt(userC.balance, userE.balance);
	}
}
