export interface IDeployConfig {
	TX_CONFIRMATIONS: number
	Setup?: ContractConfig
}

export interface ContractConfig {
	general: GeneralConfig
	gmxStaking: GMXStaking
	glpStaking: GLPStaking
}

export interface GeneralConfig {
	adminWallet: string
	vestaTreasruy: string
	activePool: string
	gmxRewardRouterV2: string
}

export interface GMXStaking {
	gmxToken: string
	stakedGmxTracker: string
	feeGmxTrackerRewards: string
}

export interface GLPStaking {
	sGLP: string
	feeGlpTrackerRewards: string
}
