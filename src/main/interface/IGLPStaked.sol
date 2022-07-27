// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IGLPStaked {
	function stake(uint256 _amount) external;

	function unstake(uint256 _amount) external;
}
