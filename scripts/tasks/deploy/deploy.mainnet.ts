import { IDeployConfig } from "../../config/DeployConfig"
import { Deployer } from "./Deployer"
import { colorLog, Colors, addColor } from "../../utils/ColorConsole"
import { HardhatRuntimeEnvironment } from "hardhat/types/runtime"
import readline from "readline-sync"

const config: IDeployConfig = {
	TX_CONFIRMATIONS: 3,
	Setup: {
		adminWallet: "0x4A4651B31d747D1DdbDDADCF1b1E24a5f6dcc7b0",
		vestaTreasruy: "0x4A4651B31d747D1DdbDDADCF1b1E24a5f6dcc7b0",
		gmxToken: "0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a",
		gmxRewardRouterV2: "0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1",
		stakedGmxTracker: "0x908C4D94D34924765f1eDc22A1DD098397c59dD4",
		feeGmxTrackerRewards: "0xd2D1162512F927a7e282Ef43a362659E4F2a728F",
		activePool: "0xBE3dE7fB9Aa09B3Fa931868Fb49d5BA5fEe2eBb1",
	},
}

export async function execute(hre: HardhatRuntimeEnvironment) {
	var userinput: string = "0"

	userinput = readline.question(
		addColor(
			Colors.yellow,
			`\nYou are about to deploy on the mainnet, is it fine? [y/N]\n`
		)
	)

	if (userinput.toLowerCase() !== "y") {
		colorLog(Colors.blue, `User cancelled the deployment!\n`)
		return
	}

	colorLog(Colors.green, `User approved the deployment\n`)

	await new Deployer(config, hre).run()
}
