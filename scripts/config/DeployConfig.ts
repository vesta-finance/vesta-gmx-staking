export interface IDeployConfig {
	TX_CONFIRMATIONS: number
	Setup: ContractConfig
}

export interface ContractConfig {
	adminWallet: string
	vestaTreasruy: string
	gmxToken: string
	gmxRewardRouterV2: string
	stakedGmxTracker: string
	feeGmxTrackerRewards: string
	activePool: string
}
