// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

contract Deposit is Script {

    address public constant DEPLOYER = 0x420ACF637D662b80cca8bEfb327AA24039E7e0Fa;

    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    address public constant USDC_YVBTC = 0x52A52d224573fCBDD6e8353cE1D0591563Fc3Bb4;

    address[3] public CBBTC_VAULTS = [
        0x7D3536382805f01b3c8c88a9a2037466C1FEd424, // cbBTC/yvUSD
        0x3a36da4424906752c97532619757E232f4970a0f, // cbBTC/ysPYUSD
        0xCba881a129A8Fe951c5909bDeCe34184B06eCafB // cbBTC/ysRLUSD
        // 0x64D67F70Fa1a6898485D69b5916E1ce1e494B026  // cbBTC/ysUSDT
    ];

    function run() public {
        uint256 _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        require(vm.addr(_pk) == DEPLOYER, "!deployer");

        vm.startBroadcast(_pk);

        // Whitelist deployer on all vaults
        IStrategyInterface(USDC_YVBTC).setAllowed(DEPLOYER, true);
        for (uint256 i = 0; i < CBBTC_VAULTS.length; i++) {
            IStrategyInterface(CBBTC_VAULTS[i]).setAllowed(DEPLOYER, true);
        }

        // Deposit all USDC into USDC/yvBTC
        uint256 _usdcBal = ERC20(USDC).balanceOf(DEPLOYER);
        if (_usdcBal > 0) {
            ERC20(USDC).approve(USDC_YVBTC, _usdcBal);
            IERC4626(USDC_YVBTC).deposit(_usdcBal, DEPLOYER);
            console.log("Deposited %s USDC into USDC/yvBTC", _usdcBal);
        }

        // Split cbBTC evenly across all cbBTC vaults
        uint256 _cbbtcBal = ERC20(CBBTC).balanceOf(DEPLOYER);
        if (_cbbtcBal > 0) {
            uint256 _perVault = _cbbtcBal / CBBTC_VAULTS.length;
            for (uint256 i = 0; i < CBBTC_VAULTS.length; i++) {
                uint256 _amount = (i == CBBTC_VAULTS.length - 1)
                    ? ERC20(CBBTC).balanceOf(DEPLOYER) // last vault gets remainder
                    : _perVault;
                ERC20(CBBTC).approve(CBBTC_VAULTS[i], _amount);
                IERC4626(CBBTC_VAULTS[i]).deposit(_amount, DEPLOYER);
                console.log("Deposited %s cbBTC into vault %s", _amount, CBBTC_VAULTS[i]);
            }
        }

        vm.stopBroadcast();

        // Print balances
        console.log("--- Balances ---");
        console.log("USDC/yvBTC shares: %s", ERC20(USDC_YVBTC).balanceOf(DEPLOYER));
        for (uint256 i = 0; i < CBBTC_VAULTS.length; i++) {
            console.log("Vault %s shares: %s", CBBTC_VAULTS[i], ERC20(CBBTC_VAULTS[i]).balanceOf(DEPLOYER));
        }
    }

}
