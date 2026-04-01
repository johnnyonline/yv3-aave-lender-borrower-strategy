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
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address public constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address public constant RLUSD = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;

    // address public constant LENDER_VAULT = 0x696d02Db93291651ED510704c9b286841d506987; // yvUSD
    // address public constant LENDER_VAULT = 0xb8787E236e699654F910CAD14F338d0DdB529Fd7; // yvBTC
    // address public constant LENDER_VAULT = 0x68E2B0A30F0c470bC4Bdc80bB9A308b0187Ca610; // pyUSD
    // address public constant LENDER_VAULT = 0x5933b3972abD1CAcc7F6a6D5a24256a17f5c8289; // rlUSD
    address public constant LENDER_VAULT = 0xA0e0B2F2F28A7A9CB16F307582B247240BAc6db0; // USDT
    address public constant ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address public constant YHAAS = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E; // yHAAS
    address public constant STRATEGY_APR_ORACLE = 0x804916A943A01E2E82304C1C0E743eAeF63D2FFd;

    ICentralAprOracle public constant APR_ORACLE = ICentralAprOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    function run() public {
        uint256 _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_pk);
        require(_deployer == DEPLOYER, "!deployer");

        string memory _name = "Aave v3 cbBTC/ysUSDT Lender Borrower";

        vm.startBroadcast(_pk);

        // deploy
        address _exchange = address(new Exchange(DEPLOYER));
        // address _aprOracle = address(new StrategyAprOracle());
        address _aprOracle = STRATEGY_APR_ORACLE;
        address _strategy = address(new Strategy(CBBTC, _name, LENDER_VAULT, ADDRESS_PROVIDER, _exchange, uint8(0)));

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
        // _setUsdcCbbtcRoute(_exchange);
        // _setPyusdCbbtcRoute(_exchange);
        // _setRlusdCbbtcRoute(_exchange);
        _setUsdtCbbtcRoute(_exchange);

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

    function _setPyusdCbbtcRoute(
        address _exchange
    ) internal {
        address _payPool = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
        address _tricryptoUSDC = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
        address _cbBtcWbtcPool = 0x839d6bDeDFF886404A6d7a788ef241e4e28F4802;

        // PYUSD -> cbBTC (PYUSD -> USDC via PayPool, USDC -> WBTC via tricrypto, WBTC -> cbBTC via stableswap)
        address[11] memory _fromRoute;
        _fromRoute[0] = PYUSD;
        _fromRoute[1] = _payPool;
        _fromRoute[2] = USDC;
        _fromRoute[3] = _tricryptoUSDC;
        _fromRoute[4] = WBTC;
        _fromRoute[5] = _cbBtcWbtcPool;
        _fromRoute[6] = CBBTC;
        uint256[5][5] memory _fromParams;
        _fromParams[0] = [uint256(0), 1, 1, 1, 2]; // PYUSD(0) -> USDC(1), stableswap
        _fromParams[1] = [uint256(0), 1, 1, 3, 3]; // USDC(0) -> WBTC(1), tricrypto
        _fromParams[2] = [uint256(1), 0, 1, 1, 2]; // WBTC(1) -> cbBTC(0), stableswap

        // cbBTC -> PYUSD (cbBTC -> WBTC via stableswap, WBTC -> USDC via tricrypto, USDC -> PYUSD via PayPool)
        address[11] memory _toRoute;
        _toRoute[0] = CBBTC;
        _toRoute[1] = _cbBtcWbtcPool;
        _toRoute[2] = WBTC;
        _toRoute[3] = _tricryptoUSDC;
        _toRoute[4] = USDC;
        _toRoute[5] = _payPool;
        _toRoute[6] = PYUSD;
        uint256[5][5] memory _toParams;
        _toParams[0] = [uint256(0), 1, 1, 1, 2]; // cbBTC(0) -> WBTC(1), stableswap
        _toParams[1] = [uint256(1), 0, 1, 3, 3]; // WBTC(1) -> USDC(0), tricrypto
        _toParams[2] = [uint256(1), 0, 1, 1, 2]; // USDC(1) -> PYUSD(0), stableswap

        address[5] memory _pools;

        Exchange(_exchange).setCurveRoute(PYUSD, CBBTC, _fromRoute, _fromParams, _pools);
        Exchange(_exchange).setCurveRoute(CBBTC, PYUSD, _toRoute, _toParams, _pools);
    }

    function _setRlusdCbbtcRoute(
        address _exchange
    ) internal {
        address _rlusdUsdcPool = 0xD001aE433f254283FeCE51d4ACcE8c53263aa186;
        address _tricryptoUSDC = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
        address _cbBtcWbtcPool = 0x839d6bDeDFF886404A6d7a788ef241e4e28F4802;

        // RLUSD -> cbBTC (RLUSD -> USDC via RLUSD/USDC, USDC -> WBTC via tricrypto, WBTC -> cbBTC via stableswap)
        address[11] memory _fromRoute;
        _fromRoute[0] = RLUSD;
        _fromRoute[1] = _rlusdUsdcPool;
        _fromRoute[2] = USDC;
        _fromRoute[3] = _tricryptoUSDC;
        _fromRoute[4] = WBTC;
        _fromRoute[5] = _cbBtcWbtcPool;
        _fromRoute[6] = CBBTC;
        uint256[5][5] memory _fromParams;
        _fromParams[0] = [uint256(1), 0, 1, 1, 2]; // RLUSD(1) -> USDC(0), stableswap
        _fromParams[1] = [uint256(0), 1, 1, 3, 3]; // USDC(0) -> WBTC(1), tricrypto
        _fromParams[2] = [uint256(1), 0, 1, 1, 2]; // WBTC(1) -> cbBTC(0), stableswap

        // cbBTC -> RLUSD (cbBTC -> WBTC via stableswap, WBTC -> USDC via tricrypto, USDC -> RLUSD via RLUSD/USDC)
        address[11] memory _toRoute;
        _toRoute[0] = CBBTC;
        _toRoute[1] = _cbBtcWbtcPool;
        _toRoute[2] = WBTC;
        _toRoute[3] = _tricryptoUSDC;
        _toRoute[4] = USDC;
        _toRoute[5] = _rlusdUsdcPool;
        _toRoute[6] = RLUSD;
        uint256[5][5] memory _toParams;
        _toParams[0] = [uint256(0), 1, 1, 1, 2]; // cbBTC(0) -> WBTC(1), stableswap
        _toParams[1] = [uint256(1), 0, 1, 3, 3]; // WBTC(1) -> USDC(0), tricrypto
        _toParams[2] = [uint256(0), 1, 1, 1, 2]; // USDC(0) -> RLUSD(1), stableswap

        address[5] memory _pools;

        Exchange(_exchange).setCurveRoute(RLUSD, CBBTC, _fromRoute, _fromParams, _pools);
        Exchange(_exchange).setCurveRoute(CBBTC, RLUSD, _toRoute, _toParams, _pools);
    }

    function _setUsdtCbbtcRoute(
        address _exchange
    ) internal {
        address _tricrypto2 = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
        address _cbBtcWbtcPool = 0x839d6bDeDFF886404A6d7a788ef241e4e28F4802;

        // USDT -> cbBTC (USDT -> WBTC via tricrypto2, WBTC -> cbBTC via stableswap)
        address[11] memory _fromRoute;
        _fromRoute[0] = USDT;
        _fromRoute[1] = _tricrypto2;
        _fromRoute[2] = WBTC;
        _fromRoute[3] = _cbBtcWbtcPool;
        _fromRoute[4] = CBBTC;
        uint256[5][5] memory _fromParams;
        _fromParams[0] = [uint256(0), 1, 1, 3, 3]; // USDT(0) -> WBTC(1), tricrypto
        _fromParams[1] = [uint256(1), 0, 1, 1, 2]; // WBTC(1) -> cbBTC(0), stableswap

        // cbBTC -> USDT (cbBTC -> WBTC via stableswap, WBTC -> USDT via tricrypto2)
        address[11] memory _toRoute;
        _toRoute[0] = CBBTC;
        _toRoute[1] = _cbBtcWbtcPool;
        _toRoute[2] = WBTC;
        _toRoute[3] = _tricrypto2;
        _toRoute[4] = USDT;
        uint256[5][5] memory _toParams;
        _toParams[0] = [uint256(0), 1, 1, 1, 2]; // cbBTC(0) -> WBTC(1), stableswap
        _toParams[1] = [uint256(1), 0, 1, 3, 3]; // WBTC(1) -> USDT(0), tricrypto

        address[5] memory _pools;

        Exchange(_exchange).setCurveRoute(USDT, CBBTC, _fromRoute, _fromParams, _pools);
        Exchange(_exchange).setCurveRoute(CBBTC, USDT, _toRoute, _toParams, _pools);
    }

}

// usdc/yvbtc
// Exchange address: 0x526b1D550c6ebC7F37528d04c1D55727d36Fcbf6
// Oracle address: 0x804916A943A01E2E82304C1C0E743eAeF63D2FFd
// Strategy address: 0xd83140cC14B0322ECaBab27D3cb6565cfea92972

// cbbtc/yvusd
// Exchange address: 0x1a6ABa508d32D27AA11caa744d2E297BC1684b68
// Oracle address: 0x804916A943A01E2E82304C1C0E743eAeF63D2FFd
// Strategy address: 0x1Ac0782d5A13549B9dd6519Bd2EBFBFdFaCb574a

// cbbtc/yspyusd
// Exchange address: 0x4E58891961693D19dC8ea1767179EdaEFA45935b
// Oracle address: 0x804916A943A01E2E82304C1C0E743eAeF63D2FFd
// Strategy address: 0x8eb033F6C45656C2f5Af610e42c1C75622f4856B

// cbbtc/ysrlusd
// Exchange address: 0xE2CFFb25bCDFCd28F940B6c0a3AC1A90735D2A73
// Oracle address: 0x804916A943A01E2E82304C1C0E743eAeF63D2FFd
// Strategy address: 0x6d1Fcdc4A00b5C9f821D937c6d1Dda857E958be2

// cbbtc/ysusdt
// Exchange address: 0x85e5AcB31EA53ac93F6dAd92BCcE1c18f8edA48D
// Oracle address: 0x804916A943A01E2E82304C1C0E743eAeF63D2FFd
// Strategy address: 0xc9d16A3f27528db30879bbaA7c364B26A5E1B8C7