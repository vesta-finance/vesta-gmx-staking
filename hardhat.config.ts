import fs from "fs"
import { secrets } from "./.secrets"

import { HardhatUserConfig, subtask, task } from "hardhat/config"
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names"
import "hardhat-preprocessor"
import "@typechain/hardhat"

import "@nomiclabs/hardhat-etherscan"
import "@nomiclabs/hardhat-waffle"
import "@openzeppelin/hardhat-upgrades"

import deploy from "./scripts/tasks/DeployTask"

task("deploy", "Deploy task")
	.addParam("env", "localhost | testnet | mainnet", "testnet")
	.setAction(deploy)

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
	async (_, __, runSuper) => {
		const paths = await runSuper()
		return paths.filter((p: string) => !p.endsWith(".t.sol") || p.includes("/mock/"))
	}
)

function getRemappings() {
	return fs
		.readFileSync("remappings.txt", "utf8")
		.split("\n")
		.filter(Boolean)
		.map(line => line.trim().split("="))
}

const config: HardhatUserConfig = {
	defaultNetwork: "localhost",
	networks: {
		localhost: {
			url: "http://localhost:8545",
		},
		arbitrumTestnet: {
			url: secrets.networks.arbitrumTestnet!.RPC_URL || "",
			accounts: [secrets.networks.arbitrumTestnet!.PRIVATE_KEY],
		},
		arbitrumOne: {
			url: secrets.networks.arbitrumOne!.RPC_URL,
			accounts: [secrets.networks.arbitrumOne!.PRIVATE_KEY],
		},
	},
	etherscan: {
		apiKey: {
			arbitrumOne: secrets.networks.arbitrumOne?.ETHERSCAN_API_KEY!,
			arbitrumTestnet: secrets.networks.arbitrumTestnet?.ETHERSCAN_API_KEY!,
		},
	},
	solidity: {
		version: "0.8.15",
		settings: {
			optimizer: {
				enabled: true,
				runs: 200,
			},
		},
	},
	paths: {
		sources: "./src",
		cache: "./hardhat/cache",
		artifacts: "./hardhat/artifacts",
	},
	preprocess: {
		eachLine: hre => ({
			transform: (line: string) => {
				if (line.match(/^\s*import /i)) {
					getRemappings().forEach(([find, replace]) => {
						if (line.match(find)) {
							line = line.replace(find, replace)
						}
					})
				}
				return line
			},
		}),
	},
}

export default config
