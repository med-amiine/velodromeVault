// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "../src/ERC4626VelodromeVault.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ERC4626VelodromeVault vault = new ERC4626VelodromeVault(
            IERC20(vm.envAddress("USDC_ADDRESS")),
            IERC20(vm.envAddress("TARGET_TOKEN_ADDRESS")),
            vm.envAddress("VELODROME_ROUTER"),
            vm.envAddress("VELODROME_FACTORY"),
            "Vault Name",
            "VAULT"
        );

        vm.stopBroadcast();
    }
}
