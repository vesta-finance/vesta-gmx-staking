// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "./BaseGMXProtocol.t.sol";
import "../common/mock/MockERC20.sol";
import { FullMath } from "../../main/lib/FullMath.sol";
import "../../main/interface/IGMXRewardRouterV2.sol";
import { IGMXRewardTracker } from "../../main/interface/IGMXRewardTracker.sol";
import { IPriceFeedV2 } from "../../main/interface/internal/IPriceFeedV2.sol";
import { VestaGLPStaking } from "../../main/VestaGLPStaking.sol";

contract VestaGLPStakingTest is BaseGMXProtocol {
	address private owner = accounts.PUBLIC_KEYS(0);
	address private operator = accounts.PUBLIC_KEYS(1);
	address private MOCK_ADDR = address(0x1);
	address private userA = address(0x001);
	address private userB = address(0x002);
	address private userC = address(0x003);
	address private userD = address(0x004);
	address private userE = address(0x005);
	address private treasury = address(0x006);
	address private priceFeed = address(0x007);
	address private fGLP = address(0x4e971a87900b931fF39d1Aad67697F49835400b6);

	uint256 private constant TOKENS_PER_INTERVAL = 1593915343915343;
	uint256 private constant GLP_PRICE = 91e16;
	uint256 private constant ETH_PRICE = 1600e18;
	uint256 private constant TOTAL_SUPPLY = 311978974401636000000000000;
	uint256 private constant YEARLY = 31_536_000; //86400 * 365
	uint256 private APY;

	address private feeGlpTrackerRewards = address(0x345);
	MockERC20 private sGLP = new MockERC20("sGLP", "sGLP", 18);
	ReentrancyAttack private reentrancyAttacker;

	VestaGLPStaking private underTest;

	function setUp() external {
		vm.deal(address(gmxRouter), 100e32);
		sGLP.mint(operator, 100_000e18);

		vm.etch(operator, address(this).code);

		underTest = new VestaGLPStaking();
		interfaceUnderTest = IVestaGMXStaking(underTest);

		vm.startPrank(owner);
		{
			underTest.setUp(
				treasury,
				address(sGLP),
				address(gmxRouter),
				feeGlpTrackerRewards
			);

			underTest.setOperator(operator, true);
			underTest.setPriceFeed(priceFeed);
		}
		vm.stopPrank();

		vm.prank(operator);
		sGLP.approve(address(underTest), type(uint256).max);

		reentrancyAttacker = new ReentrancyAttack(operator, underTest, vm);
		mockAPY();
	}

	function mockAPY() private {
		vm.mockCall(
			fGLP,
			abi.encodeWithSelector(IGMXRewardTracker.tokensPerInterval.selector),
			abi.encode(TOKENS_PER_INTERVAL)
		);

		vm.mockCall(
			feeGlpTrackerRewards,
			abi.encodeWithSelector(IGMXRewardTracker.totalSupply.selector),
			abi.encode(TOTAL_SUPPLY)
		);

		vm.mockCall(
			priceFeed,
			abi.encodeWithSelector(IPriceFeedV2.getExternalPrice.selector, address(0)),
			abi.encode(ETH_PRICE)
		);
		vm.mockCall(
			priceFeed,
			abi.encodeWithSelector(IPriceFeedV2.getExternalPrice.selector, address(sGLP)),
			abi.encode(GLP_PRICE)
		);

		APY =
			((YEARLY * TOKENS_PER_INTERVAL * ETH_PRICE) * BPS) /
			(TOTAL_SUPPLY * GLP_PRICE);
	}

	function test_setUp_whenCalledTwice_thenReverts() external {
		underTest = new VestaGLPStaking();
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR);

		vm.expectRevert(ERROR_ALREADY_INITIALIZED);
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR);
	}

	function test_setUp_withInvalidAddress_thenReverts() external {
		underTest = new VestaGLPStaking();

		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setUp(address(0), MOCK_ADDR, MOCK_ADDR, MOCK_ADDR);

		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setUp(MOCK_ADDR, address(0), MOCK_ADDR, MOCK_ADDR);

		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, address(0), MOCK_ADDR);

		vm.expectRevert(ERROR_INVALID_ADDRESS);
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, address(0));
	}

	function test_setUp_ThenCallerIsOwner() external prankAs(owner) {
		underTest = new VestaGLPStaking();
		underTest.setUp(MOCK_ADDR, MOCK_ADDR, MOCK_ADDR, MOCK_ADDR);

		assertEq(underTest.owner(), owner);
	}

	function test_setUp_thenStorageUpdated() external prankAs(owner) {
		underTest = new VestaGLPStaking();
		underTest.setUp(
			treasury,
			address(sGLP),
			address(gmxRouter),
			feeGlpTrackerRewards
		);

		assertEq(underTest.vestaTreasury(), treasury);
		assertEq(underTest.sGLP(), address(sGLP));
		assertEq(address(underTest.gmxRewardRouterV2()), address(gmxRouter));
		assertEq(address(underTest.feeGlpTrackerRewards()), feeGlpTrackerRewards);
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
			address(sGLP),
			abi.encodeWithSignature(
				"transferFrom(address,address,uint256)",
				operator,
				address(underTest),
				24e18
			)
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

	function test_stake_givenReentrancyAttacker_thenEmitsFailedToSendETH() external {
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

	function test_unstake_asOperator_givenReentrancyAttacker_thenEmitsFailedToSendETH()
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
		uint256 balanceBefore = sGLP.balanceOf(operator);

		underTest.unstake(userA, 25e17);

		assertEq(underTest.getVaultStake(userA), 25e17);
		assertEq(underTest.totalStaked(), 25e17);
		assertEq(sGLP.balanceOf(operator) - balanceBefore, 25e17);
	}

	function test_claim_asNonStaker_thenReverts() external prankAs(userA) {
		vm.expectRevert(ERROR_INSUFFICIENT_STAKE_BALANCE);
		underTest.claim();
	}

	function test_claim_asStaker_whenCalledTwice_thenGiveRewardsOnce() external {
		uint256 reward = 10e18;
		uint256 expectingReward = reward - ((reward * underTest.treasuryFee()) / BPS);

		vm.prank(operator);
		underTest.stake(userA, 100e18);

		gmxRouter.setNextReward(10e18);

		vm.startPrank(userA);
		{
			underTest.claim();
			underTest.claim();
		}
		vm.stopPrank();

		assertEq(userA.balance, expectingReward);
	}

	function test_claim_asReentrencyAttacker_thenEmitsFailedToSendETH() external {
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

	function test_setBaseTreasuryFee_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(NOT_OWNER);
		underTest.setBaseTreasuryFee(10_000);
	}

	function test_setBaseTreasuryFee_asOwner_givenFeeHigherThan2000_thenReverts()
		external
		prankAs(owner)
	{
		vm.expectRevert(ERROR_FEE_TOO_HIGH);
		underTest.setBaseTreasuryFee(2001);
	}

	function test_setBaseTreasuryFee_asOwner_givenValidBPS_thenUpdateBPS()
		external
		prankAs(owner)
	{
		underTest.setBaseTreasuryFee(1000);
		assertEq(underTest.baseTreasuryFee(), 1000);
	}

	function test_setTreasury_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(NOT_OWNER);
		underTest.setTreasury(address(0x123));
	}

	function test_setTreasury_asOwner_thenChangesTreasury() external prankAs(owner) {
		underTest.setTreasury(address(0x123));
		assertEq(underTest.vestaTreasury(), address(0x123));
	}

	function test_setPriceFeed_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(NOT_OWNER);
		underTest.setPriceFeed(address(0x123));
	}

	function test_setPriceFeed_asOwner_thenReverts() external prankAs(owner) {
		underTest.setPriceFeed(address(0x123));
		assertEq(address(underTest.priceFeed()), address(0x123));
	}

	function test_setFeeGlpTrackerReward_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(NOT_OWNER);
		underTest.setFeeGlpTrackerReward(address(0x123));
	}

	function test_setFeeGlpTrackerReward_asOwner_thenUpdateAddress()
		external
		prankAs(owner)
	{
		underTest.setFeeGlpTrackerReward(address(0x123));
		assertEq(address(underTest.feeGlpTrackerRewards()), address(0x123));
	}

	function test_treasuryFee_givenAPYHigherThan25Percent_thenAddExtraToBaseFee()
		external
	{
		assertEq(underTest.treasuryFee(), BPS - ((2000 * BPS) / APY));
	}

	function test_treasuryFee_givenAPYLowerThan25Percent_thenAddExtraToBaseFee()
		external
	{
		vm.clearMockedCalls();

		vm.mockCall(
			fGLP,
			abi.encodeWithSelector(IGMXRewardTracker.tokensPerInterval.selector),
			abi.encode(0.0014 ether)
		);

		vm.mockCall(
			feeGlpTrackerRewards,
			abi.encodeWithSelector(IGMXRewardTracker.totalSupply.selector),
			abi.encode(TOTAL_SUPPLY)
		);

		vm.mockCall(
			priceFeed,
			abi.encodeWithSelector(IPriceFeedV2.getExternalPrice.selector, address(0)),
			abi.encode(ETH_PRICE)
		);
		vm.mockCall(
			priceFeed,
			abi.encodeWithSelector(IPriceFeedV2.getExternalPrice.selector, address(sGLP)),
			abi.encode(GLP_PRICE)
		);

		//Mocked APY == 2488;
		assertEq(underTest.treasuryFee(), 2000);
	}

	function test_applyNewFeeFlow_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(NOT_OWNER);
		underTest.applyNewFeeFlow();
	}

	function test_applyNewFeeFlow_asOwner_whenFunctionAlreadyCalled_thenReverts()
		external
		prankAs(owner)
	{
		underTest.applyNewFeeFlow();
		vm.expectRevert("Function already called");
		underTest.applyNewFeeFlow();
	}

	function test_applyNewFeeFlow_asOwner_whenSystemWasAlreadyRunning_thenDoCorrection()
		external
		prankAs(owner)
	{
		uint256 rawReward = 4.52e18;
		uint256 rawRewardAfterFee = _applyTreasuryFee(rawReward) - 1; // roundDown

		changePrank(operator);
		underTest.stake(userA, 23e18);
		underTest.stake(userB, 23e18);
		gmxRouter.setNextReward(rawReward);

		changePrank(owner);
		underTest.applyNewFeeFlow();

		changePrank(operator);
		underTest.unstake(userA, 0);
		underTest.unstake(userB, 0);

		assertEq(rawRewardAfterFee / 2, userA.balance);
		assertEq(rawRewardAfterFee / 2, userB.balance);
	}

	function test_enableStaticTreasuryFee_asUser_thenReverts()
		external
		prankAs(userA)
	{
		vm.expectRevert(NOT_OWNER);
		underTest.enableStaticTreasuryFee(true);
	}

	function test_enableStaticTreasuryFee_asOwner_givenTrue_thenEnableStaticFeeAndTreasuryFeeReturnBaseFee()
		external
		prankAs(owner)
	{
		underTest.enableStaticTreasuryFee(true);
		assertTrue(underTest.useStaticFee());
		assertEq(underTest.treasuryFee(), underTest.baseTreasuryFee());
	}

	function test_enableStaticTreasuryFee_asOwner_givenFalse_whenFeeHigherThan20Percent_thenDisableAndCorrectFee()
		external
		prankAs(owner)
	{
		underTest.enableStaticTreasuryFee(true);
		underTest.setBaseTreasuryFee(2001);

		underTest.enableStaticTreasuryFee(false);
		assertTrue(!underTest.useStaticFee());
		assertEq(underTest.baseTreasuryFee(), 2000);
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
		uint256 expectedReward = reward - ((reward * underTest.treasuryFee()) / BPS);

		underTest.stake(userA, 30e18);
		gmxRouter.setNextReward(10e15);
		underTest.stake(userB, 30e18);

		vm.mockCall(
			feeGlpTrackerRewards,
			abi.encodeWithSignature("claimable(address)", address(underTest)),
			abi.encode(10e15)
		);

		assertEq(underTest.getVaultOwnerClaimable(userA), expectedReward);
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

