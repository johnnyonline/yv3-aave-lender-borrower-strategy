// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";
import {ICentralAprOracle} from "../src/interfaces/ICentralAprOracle.sol";
import {IExchange} from "../src/interfaces/IExchange.sol";

import {StrategyAprOracle} from "../src/periphery/StrategyAprOracle.sol";
import {Exchange} from "../src/periphery/Exchange.sol";

import {AaveLenderBorrowerStrategy as Strategy} from "../src/Strategy.sol";

// ---- Usage ----

// deploy:
// forge script script/Deploy.s.sol:Deploy --verify -g 250 --slow --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

contract Deploy is Script {

    address public constant SMS = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7; // SMS mainnet
    address public constant ACCOUNTANT = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69; // SMS mainnet accountant
    address public constant DEPLOYER = 0x420ACF637D662b80cca8bEfb327AA24039E7e0Fa; // gm.johnnyonline.eth

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    // address public constant LENDER_VAULT = 0x696d02Db93291651ED510704c9b286841d506987; // yvUSD
    address public constant LENDER_VAULT = 0xb8787E236e699654F910CAD14F338d0DdB529Fd7; // yvBTC
    address public constant ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address public constant YHAAS = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E; // yHAAS

    ICentralAprOracle public constant APR_ORACLE = ICentralAprOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    function run() public {
        uint256 _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_pk);
        require(_deployer == DEPLOYER, "!deployer");

        string memory _name = "Aave v3 USDC/yvBTC Lender Borrower";

        vm.startBroadcast(_pk);

        // deploy
        address _exchange = address(new Exchange(DEPLOYER, CBBTC, USDC));
        address _aprOracle = address(new StrategyAprOracle());
        address _strategy = address(new Strategy(USDC, _name, LENDER_VAULT, ADDRESS_PROVIDER, _exchange, uint8(0)));

        IStrategyInterface strategy_ = IStrategyInterface(_strategy);

        // init
        strategy_.setPerformanceFeeRecipient(ACCOUNTANT);
        strategy_.setKeeper(YHAAS);
        strategy_.setPendingManagement(SMS);
        strategy_.setEmergencyAdmin(SMS);

        // force leverage
        strategy_.setForceLeverage(true);

        // set APR oracle
        APR_ORACLE.setOracle(_strategy, _aprOracle);

        // set exchange routes
        _setUsdcCbbtcRoute(_exchange);

        // transfer exchange ownership to SMS
        Exchange(_exchange).transferOwnership(SMS);

        vm.stopBroadcast();

        console.log("Exchange address: %s", _exchange);
        console.log("Oracle address: %s", _aprOracle);
        console.log("Strategy address: %s", _strategy);
    }

    function _setUsdcCbbtcRoute(
        address _exchange
    ) internal {
        address _tricryptoUSDC = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
        address _cbBtcWbtcPool = 0x839d6bDeDFF886404A6d7a788ef241e4e28F4802;

        // USDC -> cbBTC (USDC -> WBTC via tricrypto, WBTC -> cbBTC via stableswap)
        address[11] memory _fromRoute;
        _fromRoute[0] = USDC;
        _fromRoute[1] = _tricryptoUSDC;
        _fromRoute[2] = WBTC;
        _fromRoute[3] = _cbBtcWbtcPool;
        _fromRoute[4] = CBBTC;
        uint256[5][5] memory _fromParams;
        _fromParams[0] = [uint256(0), 1, 1, 3, 3]; // USDC(0) -> WBTC(1), tricrypto
        _fromParams[1] = [uint256(1), 0, 1, 1, 2]; // WBTC(1) -> cbBTC(0), stableswap

        // cbBTC -> USDC (cbBTC -> WBTC via stableswap, WBTC -> USDC via tricrypto)
        address[11] memory _toRoute;
        _toRoute[0] = CBBTC;
        _toRoute[1] = _cbBtcWbtcPool;
        _toRoute[2] = WBTC;
        _toRoute[3] = _tricryptoUSDC;
        _toRoute[4] = USDC;
        uint256[5][5] memory _toParams;
        _toParams[0] = [uint256(0), 1, 1, 1, 2]; // cbBTC(0) -> WBTC(1), stableswap
        _toParams[1] = [uint256(1), 0, 1, 3, 3]; // WBTC(1) -> USDC(0), tricrypto

        address[5] memory _pools;

        Exchange(_exchange).setCurveRoute(USDC, CBBTC, _fromRoute, _fromParams, _pools);
        Exchange(_exchange).setCurveRoute(CBBTC, USDC, _toRoute, _toParams, _pools);
    }

}

// unaudited
// Exchange address: 0x6Cd733c283EF09A760e330acB7D8C7e9961063b4
// Oracle address: 0xe299634135b4f0037344eDE02E4A98e28DfBa79e
// Strategy address: 0x0851eedf2A2EA59a5CB688FCC4697d624fcc0576

// usdc/yvbtc
// Exchange address: 0xf46cbBCBE2b8D4dfB19c44652C1d015De1333C02
// Oracle address: 0xf7D9499a3F2FF64F56f672568de6865DAb709f83
// Strategy address: 0x4B50Da7a11d15F232378b1B35EAc1F1952C3aB7f
