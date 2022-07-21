// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.15;

import "../common/base/BaseTest.t.sol";
import "../common/mock/MockERC20.sol";
import { FullMath } from "../../main/lib/FullMath.sol";
import "../../main/interface/IGMXRewardRouterV2.sol";
import { VestaGMXStaking } from "../../main/VestaGMXStaking.sol";

contract VestaGMXStakingTest is BaseTest {
	struct UserStake {
		uint256 id;
		address wallet;
		uint256 staking;
	}

	struct ExpectedActionHarvest {
		uint256[30] usersShare;
		uint256 totalStaked;
		uint256 currentRewards;
		uint256 totalBalance;
	}

	struct ExpectedHarvestResult {
		uint256[30] toUser;
		uint256 toTreasury;
	}

	uint256 private constant PRECISION = 1e27;

	bytes private constant ERROR_REENTRANCY_DETECTED =
		abi.encodeWithSignature("ReentrancyDetected()");
	bytes private constant ERROR_ALREADY_INITIALIZED =
		"Initializable: contract is already initialized";
	string private constant ERROR_CALLER_NOT_OPERATOR_SIG =
		"CallerIsNotAnOperator(address)";
	bytes private constant ERROR_ZERO_AMOUNT_PASSED =
		abi.encodeWithSignature("ZeroAmountPassed()");
	bytes private constant ERROR_INVALID_ADDRESS =
		abi.encodeWithSignature("InvalidAddress()");
	bytes private constant ERROR_INSUFFICIENT_STAKE_BALANCE =
		abi.encodeWithSignature("InsufficientStakeBalance()");
	string private constant ERROR_ETH_TRANSFER_FAILED_SIG =
		"ETHTransferFailed(address,uint256)";
	bytes private constant ERROR_BPS_HIGHER_THAN_100 =
		abi.encodeWithSignature("BPSHigherThanOneHundred()");

	bytes private constant GMX_HANDLE_REWARDS_CALL =
		abi.encodeWithSignature(
			"handleRewards(bool,bool,bool,bool,bool,bool,bool)",
			true,
			true,
			true,
			true,
			true,
			true,
			true
		);

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
	MockGMXRouter private gmxRouter = new MockGMXRouter();
	ReentrancyAttack private reentrancyAttacker;

	VestaGMXStaking private underTest;

	function setUp() external {
		vm.deal(address(gmxRouter), 100e32);
		GMX.mint(operator, 100_000e18);

		vm.etch(operator, address(this).code);

		underTest = new VestaGMXStaking();
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
		assertEq(underTest.lastBalance(), 12e18);
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
		underTest.stake(userA, 1e18);
		gmxRouter.setNextReward(3e18);
		underTest.stake(userA, 2e18);

		uint256 expectedBalanceTreasury = (3e18 / 10_000) * underTest.treasuryFee();
		uint256 expectedBalanceUser = 3e18 - expectedBalanceTreasury;
		uint256 expectedNewRewardShare = (3e18 * PRECISION) / 1e18;

		assertEq(userA.balance, expectedBalanceUser);
		assertEq(treasury.balance, expectedBalanceTreasury);
		assertEq(underTest.rewardShare(), expectedNewRewardShare);
	}

	function test_stake_asOperator_givenNotFirstStakerAndNonZeroRewardShare_thenUpdateStakerOriginalShareWithNewRewardShare()
		external
		prankAs(operator)
	{
		underTest.stake(userA, 2e18);
		gmxRouter.setNextReward(3e18);
		underTest.stake(userB, 4e18);

		uint256 expectedNewRewardShare = (3e18 * PRECISION) / 2e18;
		uint256 expectedOriginalShare = (4e18 * expectedNewRewardShare) / PRECISION;

		assertEq(underTest.getVaultOwnerShare(userB), expectedOriginalShare);
	}

	function test_stake_givenReentrancyAttacker_thenReverts() external {
		vm.deal(address(underTest), 1000e18);

		vm.prank(operator);
		underTest.stake(address(reentrancyAttacker), 100e18);

		gmxRouter.setNextReward(1e18);

		vm.expectRevert(
			abi.encodeWithSignature(
				ERROR_ETH_TRANSFER_FAILED_SIG,
				address(reentrancyAttacker),
				8e17
			)
		);
		vm.prank(operator);
		underTest.stake(address(reentrancyAttacker), 1e18);

		assertEq(address(reentrancyAttacker).balance, 0);
	}

	function test_unstake_asUser_thenReverts() external prankAs(userA) {
		vm.expectRevert(abi.encodeWithSignature(ERROR_CALLER_NOT_OPERATOR_SIG, userA));
		underTest.unstake(userA, 1e18);
	}

	function test_unstake_asOperator_givenReentrancyAttacker_thenReverts()
		external
		prankAs(operator)
	{
		vm.deal(address(underTest), 30e18);
		underTest.stake(address(reentrancyAttacker), 1e18);
		gmxRouter.setNextReward(1e18);

		vm.expectRevert(
			abi.encodeWithSignature(
				ERROR_ETH_TRANSFER_FAILED_SIG,
				address(reentrancyAttacker),
				8e17
			)
		);

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

	function test_claim_asStaker_whenCalledTwice_thenGiveRewardsOnce() external {
		vm.prank(operator);
		underTest.stake(userA, 100e18);

		gmxRouter.setNextReward(10e18);

		vm.startPrank(userA);
		{
			underTest.claim();
			underTest.claim();
		}
		vm.stopPrank();

		assertEq(userA.balance, 8e18);
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
		underTest.setTreasuryFee(10_000);
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
		underTest.stake(userA, 30e18);
		gmxRouter.setNextReward(10e15);
		underTest.stake(userB, 30e18);

		vm.mockCall(
			feeGmxTrackerRewards,
			abi.encodeWithSignature("claimable(address)", address(underTest)),
			abi.encode(10e15)
		);

		uint256 expectedReward = 15e15;
		uint256 treasuryFee = (((expectedReward * PRECISION) / 10_000) * 2_000) /
			PRECISION;

		assertEq(underTest.getVaultOwnerClaimable(userA), expectedReward - treasuryFee);
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
		assertEq(treasury.balance, results.toTreasury);

		assertGt(userA.balance, userB.balance);
		assertGt(userB.balance, userC.balance);
		assertGt(userD.balance, userC.balance);
		assertGt(userC.balance, userE.balance);
	}

	function _stakeWithEstimation(
		uint256 nextReward,
		UserStake memory user,
		ExpectedActionHarvest memory expectedActions
	) internal returns (ExpectedActionHarvest memory) {
		uint256 totalBalance = expectedActions.totalBalance;

		gmxRouter.setNextReward(nextReward);

		underTest.stake(user.wallet, user.staking);
		expectedActions.currentRewards += getExtraEstimationShare(
			(totalBalance + nextReward) - totalBalance,
			expectedActions.totalStaked
		);

		expectedActions.totalStaked += user.staking;

		expectedActions.usersShare[user.id] = getEstimationUserShare(
			user.staking,
			expectedActions.currentRewards,
			true
		);

		expectedActions.totalBalance += nextReward;

		return expectedActions;
	}

	function _getHarvestReward(
		uint256 extraNewEth,
		UserStake memory user,
		ExpectedActionHarvest memory actionHarvest,
		ExpectedHarvestResult memory results
	)
		internal
		view
		returns (ExpectedActionHarvest memory, ExpectedHarvestResult memory)
	{
		uint256 balance = actionHarvest.totalBalance;
		uint256 originalShare = actionHarvest.usersShare[user.id];

		actionHarvest.currentRewards += getExtraEstimationShare(
			(balance + extraNewEth) - balance,
			actionHarvest.totalStaked
		);

		uint256 expectedCurrentShare = getEstimationUserShare(
			user.staking,
			actionHarvest.currentRewards,
			false
		);

		if (expectedCurrentShare > originalShare) {
			uint256 userTotalReward = expectedCurrentShare - originalShare;
			uint256 toTreasury = (((userTotalReward * PRECISION) / 10_000) *
				underTest.treasuryFee()) / PRECISION;
			uint256 toUser = userTotalReward - toTreasury;

			actionHarvest.totalBalance =
				(actionHarvest.totalBalance + extraNewEth) -
				userTotalReward;

			results.toUser[user.id] = toUser;
			results.toTreasury += toTreasury;
		}
		return (actionHarvest, results);
	}

	function getExtraEstimationShare(uint256 balanceDiff, uint256 totalStakes)
		internal
		pure
		returns (uint256)
	{
		return
			totalStakes > 0 ? FullMath.mulDiv(balanceDiff, PRECISION, totalStakes) : 0;
	}

	function getEstimationUserShare(
		uint256 staking,
		uint256 estimationShare,
		bool roundUp
	) internal pure returns (uint256) {
		return
			roundUp
				? FullMath.mulDivRoundingUp(staking, estimationShare, PRECISION)
				: FullMath.mulDiv(staking, estimationShare, PRECISION);
	}
}

contract MockGMXRouter is IGMXRewardRouterV2 {
	uint256 nextRewardETH = 0;

	function setNextReward(uint256 eth) external {
		nextRewardETH = eth;
	}

	function stakeGmx(uint256 _amount) external override {}

	function unstakeGmx(uint256 _amount) external override {}

	function handleRewards(
		bool _shouldClaimGmx,
		bool _shouldStakeGmx,
		bool _shouldClaimEsGmx,
		bool _shouldStakeEsGmx,
		bool _shouldStakeMultiplierPoints,
		bool _shouldClaimWeth,
		bool _shouldConvertWethToEth
	) external override {
		_shouldClaimGmx = true;
		_shouldStakeGmx = true;
		_shouldClaimEsGmx = true;
		_shouldStakeEsGmx = true;
		_shouldStakeMultiplierPoints = true;
		_shouldClaimWeth = true;
		_shouldConvertWethToEth = true;

		(bool success, ) = msg.sender.call{ value: nextRewardETH }("");
		require(success, "failed to send eth");

		nextRewardETH = 0;
	}
}

contract ReentrancyAttack {
	bytes private constant ERROR_REENTRANCY_DETECTED =
		abi.encodeWithSignature("ReentrancyDetected()");

	address operator;
	VestaGMXStaking underTest;
	Vm vm;

	constructor(
		address _operator,
		VestaGMXStaking _underTest,
		Vm _vm
	) {
		operator = _operator;
		underTest = _underTest;
		vm = _vm;
	}

	receive() external payable {
		vm.prank(operator);
		underTest.unstake(address(this), 0);
	}
}
