import { ContractConfig, IDeployConfig } from "../../config/DeployConfig"
import { DeploymentHelper } from "../../utils/DeploymentHelper"
import { HardhatRuntimeEnvironment } from "hardhat/types/runtime"
import { HardhatEthersHelpers } from "@nomiclabs/hardhat-ethers/types"
import { Contract } from "ethers"

export class Deployer {
	config: IDeployConfig
	helper: DeploymentHelper
	ethers: HardhatEthersHelpers
	hre: HardhatRuntimeEnvironment
	setup: ContractConfig

	constructor(config: IDeployConfig, hre: HardhatRuntimeEnvironment) {
		this.hre = hre
		this.ethers = hre.ethers
		this.config = config
		this.helper = new DeploymentHelper(config, hre)
		this.setup = this.config.Setup!

		if (this.setup === undefined) throw "Setup not configured"
	}

	async run() {
		await this.GMXStaking()
		await this.GLPStaking()

		const adminProxy = await this.hre.upgrades.admin.getInstance()
		if ((await adminProxy.owner()) !== this.setup.general.adminWallet) {
			this.hre.upgrades.admin.transferProxyAdminOwnership(
				this.setup.general.adminWallet
			)
		}
	}

	async GMXStaking() {
		const e = await this.hre.upgrades.prepareUpgrade("0xDB607928F10Ca503Ee6678522567e80D8498D759", await this.hre.ethers.getContractFactory("VestaGLPStaking"));
		console.log(e);

		throw e;

		const vestaGMX = await this.helper.deployUpgradeableContractWithName(
			"VestaGMXStaking",
			"VestaGMXStaking",
			"setUp",
			this.setup.general.vestaTreasruy,
			this.setup.gmxStaking.gmxToken,
			this.setup.general.gmxRewardRouterV2,
			this.setup.gmxStaking.stakedGmxTracker,
			this.setup.gmxStaking.feeGmxTrackerRewards
		)

		if (!(await vestaGMX.isOperator(this.setup.general.activePool))) {
			await this.helper.sendAndWaitForTransaction(
				vestaGMX.setOperator(this.setup.general.activePool, true)
			)
		}

		await this.tryGiveOwnership(vestaGMX)
	}

	async GLPStaking() {
		const vestaGLP = await this.helper.deployUpgradeableContractWithName(
			"VestaGLPStaking",
			"VestaGLPStaking",
			"setUp",
			this.setup.general.vestaTreasruy,
			this.setup.glpStaking.sGLP,
			this.setup.general.gmxRewardRouterV2,
			this.setup.glpStaking.feeGlpTrackerRewards
		)


		if (!(await vestaGLP.isOperator(this.setup.general.activePool))) {
			await this.helper.sendAndWaitForTransaction(
				vestaGLP.setOperator(this.setup.general.activePool, true)
			)
		}

		await this.tryGiveOwnership(vestaGLP)
	}

	async tryGiveOwnership(contract: Contract) {
		if ((await contract.owner()) !== this.setup.general.adminWallet) {
			await this.helper.sendAndWaitForTransaction(
				contract.transferOwnership(this.setup.general.adminWallet)
			)
		}
	}
}
