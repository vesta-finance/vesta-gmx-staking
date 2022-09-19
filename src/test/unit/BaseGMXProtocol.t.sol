// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

import { BaseTest, console, Vm } from "../common/base/BaseTest.t.sol";
import { FullMath } from "../../main/lib/FullMath.sol";
import { IVestaGMXStaking } from "../../main/interface/IVestaGMXStaking.sol";
import "../common/mock/MockERC20.sol";

import "../../main/interface/IGMXRewardRouterV2.sol";

abstract contract BaseGMXProtocol is BaseTest {
	event FailedToSendETH(address indexed to, uint256 _amount);

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

	uint256 internal constant PRECISION = 1e27;
	uint256 internal constant BPS = 10_000;

	bytes internal constant ERROR_REENTRANCY_DETECTED =
		abi.encodeWithSignature("ReentrancyDetected()");
	bytes internal constant ERROR_ALREADY_INITIALIZED =
		"Initializable: contract is already initialized";
	string internal constant ERROR_CALLER_NOT_OPERATOR_SIG =
		"CallerIsNotAnOperator(address)";
	bytes internal constant ERROR_ZERO_AMOUNT_PASSED =
		abi.encodeWithSignature("ZeroAmountPassed()");
	bytes internal constant ERROR_INVALID_ADDRESS =
		abi.encodeWithSignature("InvalidAddress()");
	bytes internal constant ERROR_INSUFFICIENT_STAKE_BALANCE =
		abi.encodeWithSignature("InsufficientStakeBalance()");
	string internal constant ERROR_ETH_TRANSFER_FAILED_SIG =
		"ETHTransferFailed(address,uint256)";
	bytes internal constant ERROR_BPS_HIGHER_THAN_100 =
		abi.encodeWithSignature("BPSHigherThanOneHundred()");
	bytes internal constant ERROR_FEE_TOO_HIGH =
		abi.encodeWithSignature("FeeTooHigh()");

	bytes internal constant GMX_HANDLE_REWARDS_CALL =
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

	MockGMXRouter internal gmxRouter = new MockGMXRouter();
	IVestaGMXStaking internal interfaceUnderTest;

	function _stakeWithEstimation(
		uint256 nextReward,
		UserStake memory user,
		ExpectedActionHarvest memory expectedActions
	) internal returns (ExpectedActionHarvest memory) {
		uint256 totalBalance = expectedActions.totalBalance;

		gmxRouter.setNextReward(nextReward);

		nextReward = _applyTreasuryFee(nextReward);

		interfaceUnderTest.stake(user.wallet, user.staking);
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

	function _applyTreasuryFee(uint256 _amount) internal view returns (uint256) {
		return _amount - ((_amount * interfaceUnderTest.treasuryFee()) / BPS);
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
		uint256 extraNewEthFee = _applyTreasuryFee(extraNewEth);

		actionHarvest.currentRewards += getExtraEstimationShare(
			(balance + extraNewEthFee) - balance,
			actionHarvest.totalStaked
		);

		uint256 expectedCurrentShare = getEstimationUserShare(
			user.staking,
			actionHarvest.currentRewards,
			false
		);

		if (expectedCurrentShare > originalShare) {
			uint256 userTotalReward = expectedCurrentShare - originalShare;
			uint256 toUser = userTotalReward;

			actionHarvest.totalBalance =
				(actionHarvest.totalBalance + extraNewEth) -
				userTotalReward;

			results.toUser[user.id] = toUser;
			results.toTreasury += extraNewEth - extraNewEthFee;
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
	address operator;
	IVestaGMXStaking underTest;
	Vm vm;

	constructor(
		address _operator,
		IVestaGMXStaking _underTest,
		Vm _vm
	) {
		operator = _operator;
		underTest = _underTest;
		vm = _vm;
	}

	receive() external payable {
		vm.stopPrank();
		vm.prank(operator);
		underTest.unstake(address(this), 0);
	}
}
