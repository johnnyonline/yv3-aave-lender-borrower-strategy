// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
import {ICentralAprOracle} from "../src/interfaces/ICentralAprOracle.sol";
import {IExchange} from "../src/interfaces/IExchange.sol";

import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {WBTCToUSDCExchange as Exchange} from "../src/periphery/WBTCToUSDCExchange.sol";

import {AaveLenderBorrowerStrategy as Strategy} from "../src/Strategy.sol";

// ---- Usage ----

// deploy:
// forge script script/Deploy.s.sol:Deploy --verify -g 250 --slow --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

contract Deploy is Script {

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7; // SMS mainnet
    address public constant ACCOUNTANT = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69; // SMS mainnet accountant
    address public constant DEPLOYER = 0x285E3b1E82f74A99D07D2aD25e159E75382bB43B; // johnnyonline.eth

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant LENDER_VAULT = 0x696d02Db93291651ED510704c9b286841d506987; // yvUSD
    address public constant ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address public constant YHAAS = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E; // yHAAS

    ICentralAprOracle public constant APR_ORACLE = ICentralAprOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    function run() public {
        uint256 _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_pk);
        require(_deployer == DEPLOYER, "!deployer");

        string memory _name = "Aave v3 WBTC/USDC Lender Borrower";

        vm.startBroadcast(_pk);

        // deploy
        address _exchange = address(new Exchange());
        address _aprOracle = address(new StrategyAprOracle());
        address _strategy = address(new Strategy(WBTC, _name, LENDER_VAULT, ADDRESS_PROVIDER, _exchange, uint8(0)));

        IStrategyInterface strategy_ = IStrategyInterface(_strategy);

        // init
        strategy_.setPerformanceFeeRecipient(ACCOUNTANT);
        strategy_.setKeeper(YHAAS);
        strategy_.setPendingManagement(SMS);
        strategy_.setEmergencyAdmin(SMS);

        // force leverage
        strategy_.forceLeverage();

        // set APR oracle
        APR_ORACLE.setOracle(_strategy, _aprOracle);

        vm.stopBroadcast();

        console.log("Exchange address: %s", address(_exchange));
        console.log("Oracle address: %s", address(_aprOracle));
        console.log("Strategy address: %s", address(_strategy));
    }

}

// Exchange address: 0x6Cd733c283EF09A760e330acB7D8C7e9961063b4
// Oracle address: 0xe299634135b4f0037344eDE02E4A98e28DfBa79e
// Strategy address: 0x0851eedf2A2EA59a5CB688FCC4697d624fcc0576