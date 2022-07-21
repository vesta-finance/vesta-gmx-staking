import { IDeployConfig } from "../../config/DeployConfig"
import { DeploymentHelper } from "../../utils/DeploymentHelper"
import { HardhatRuntimeEnvironment } from "hardhat/types/runtime"
import { HardhatEthersHelpers } from "@nomiclabs/hardhat-ethers/types"
import { colorLog, Colors } from "../../utils/ColorConsole"
import { Contract } from "ethers"

export class Deployer {
	config: IDeployConfig
	helper: DeploymentHelper
	ethers: HardhatEthersHelpers
	hre: HardhatRuntimeEnvironment

	constructor(config: IDeployConfig, hre: HardhatRuntimeEnvironment) {
		this.hre = hre
		this.ethers = hre.ethers
		this.config = config
		this.helper = new DeploymentHelper(config, hre)
	}

	async run() {
		const [signer] = await this.ethers.getSigners()
		const setup = this.config.Setup

		const vestaGMX = await this.helper.deployUpgradeableContractWithName(
			"VestaGMXStaking",
			"VestaGMXStaking",
			"setUp",
			[
				setup.vestaTreasruy,
				setup.gmxToken,
				setup.gmxRewardRouterV2,
				setup.stakedGmxTracker,
				setup.feeGmxTrackerRewards,
			]
		)

		await this.helper.sendAndWaitForTransaction(
			vestaGMX.setOperator(setup.activePool, true)
		)

		await this.helper.sendAndWaitForTransaction(
			vestaGMX.transferOwnership(setup.adminWallet)
		)
	}
}
