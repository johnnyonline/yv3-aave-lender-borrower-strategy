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
    address public constant YHAAS = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    address public constant PYUSD = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address public constant RLUSD = 0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address public constant ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address public constant STRATEGY_APR_ORACLE = 0x804916A943A01E2E82304C1C0E743eAeF63D2FFd;
    address public constant EXCHANGE = 0xEbb2908D09eCf29924CfB0dFa28687491EcdEaF0;

    ICentralAprOracle public constant APR_ORACLE = ICentralAprOracle(0x1981AD9F44F2EA9aDd2dC4AD7D075c102C70aF92);

    struct StrategyConfig {
        address asset;
        address lenderVault;
        string name;
        function(address) internal setRoute;
    }

    function run() public {
        uint256 _pk = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address _deployer = vm.addr(_pk);
        require(_deployer == DEPLOYER, "!deployer");

        vm.startBroadcast(_pk);

        // Deploy shared periphery
        address _exchange = EXCHANGE;
        address _aprOracle = STRATEGY_APR_ORACLE;

        address _lender = 0xb8787E236e699654F910CAD14F338d0DdB529Fd7; // yvBTC
        address _strategy = address(
            new Strategy(USDC, "Aave v3 USDC/yvBTC Lender Borrower", _lender, ADDRESS_PROVIDER, _exchange, uint8(0))
        );

        IStrategyInterface strategy_ = IStrategyInterface(_strategy);
        strategy_.setPerformanceFeeRecipient(ACCOUNTANT);
        strategy_.setKeeper(YHAAS);
        strategy_.setPendingManagement(SMS);
        strategy_.setEmergencyAdmin(SMS);
        strategy_.setForceLeverage(true);

        APR_ORACLE.setOracle(_strategy, _aprOracle);

        console.log("Strategy [%s]: %s", "Aave v3 USDC/yvBTC Lender Borrower", _strategy);

        // // Set all exchange routes
        // _setUsdcCbbtcRoute(_exchange);
        // _setPyusdCbbtcRoute(_exchange);
        // _setRlusdCbbtcRoute(_exchange);
        // _setUsdtCbbtcRoute(_exchange);

        // // Transfer exchange ownership to SMS
        // Exchange(_exchange).transferOwnership(SMS);

        // // Deploy all strategies
        // address[4] memory _assets = [USDC, PYUSD, RLUSD, USDT];
        // address[4] memory _vaults = [
        //     0x696d02Db93291651ED510704c9b286841d506987, // yvUSD
        //     0x68E2B0A30F0c470bC4Bdc80bB9A308b0187Ca610, // ysPYUSD
        //     0x5933b3972abD1CAcc7F6a6D5a24256a17f5c8289, // ysRLUSD
        //     0xA0e0B2F2F28A7A9CB16F307582B247240BAc6db0  // ysUSDT
        // ];

        // for (uint256 i = 0; i < _assets.length; i++) {
        //     address _strategy = address(
        //         new Strategy(CBBTC, _strategyName(_assets[i]), _vaults[i], ADDRESS_PROVIDER, _exchange, uint8(0))
        //     );

        //     IStrategyInterface strategy_ = IStrategyInterface(_strategy);
        //     strategy_.setPerformanceFeeRecipient(ACCOUNTANT);
        //     strategy_.setKeeper(YHAAS);
        //     strategy_.setPendingManagement(SMS);
        //     strategy_.setEmergencyAdmin(SMS);
        //     strategy_.setForceLeverage(true);

        //     APR_ORACLE.setOracle(_strategy, _aprOracle);

        //     console.log("Strategy [%s]: %s", _strategyName(_assets[i]), _strategy);
        // }

        console.log("Exchange: %s", _exchange);
        console.log("Oracle: %s", _aprOracle);

        vm.stopBroadcast();
    }

    function _strategyName(address _borrowToken) internal pure returns (string memory) {
        if (_borrowToken == USDC) return "Aave v3 cbBTC/yvUSD Lender Borrower";
        if (_borrowToken == PYUSD) return "Aave v3 cbBTC/ysPYUSD Lender Borrower";
        if (_borrowToken == RLUSD) return "Aave v3 cbBTC/ysRLUSD Lender Borrower";
        if (_borrowToken == USDT) return "Aave v3 cbBTC/ysUSDT Lender Borrower";
        revert("unknown token");
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

    function _setUsdcWstethRoute(
        address _exchange
    ) internal {
        address _crvusdUsdc = 0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E;
        address _tricryptollama = 0x2889302a794dA87fBF1D6Db415C1492194663D13;

        // USDC -> wstETH (USDC -> crvUSD via crvUSD/USDC, crvUSD -> wstETH via tricryptollama)
        address[11] memory _fromRoute;
        _fromRoute[0] = USDC;
        _fromRoute[1] = _crvusdUsdc;
        _fromRoute[2] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD
        _fromRoute[3] = _tricryptollama;
        _fromRoute[4] = WSTETH;
        uint256[5][5] memory _fromParams;
        _fromParams[0] = [uint256(0), 1, 1, 1, 2]; // USDC(0) -> crvUSD(1), stableswap
        _fromParams[1] = [uint256(0), 2, 1, 3, 3]; // crvUSD(0) -> wstETH(2), tricrypto

        // wstETH -> USDC (wstETH -> crvUSD via tricryptollama, crvUSD -> USDC via crvUSD/USDC)
        address[11] memory _toRoute;
        _toRoute[0] = WSTETH;
        _toRoute[1] = _tricryptollama;
        _toRoute[2] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD
        _toRoute[3] = _crvusdUsdc;
        _toRoute[4] = USDC;
        uint256[5][5] memory _toParams;
        _toParams[0] = [uint256(2), 0, 1, 3, 3]; // wstETH(2) -> crvUSD(0), tricrypto
        _toParams[1] = [uint256(1), 0, 1, 1, 2]; // crvUSD(1) -> USDC(0), stableswap

        address[5] memory _pools;

        Exchange(_exchange).setCurveRoute(USDC, WSTETH, _fromRoute, _fromParams, _pools);
        Exchange(_exchange).setCurveRoute(WSTETH, USDC, _toRoute, _toParams, _pools);
    }

}

// Strategy [Aave v3 USDC/yvBTC Lender Borrower]: 0x52A52d224573fCBDD6e8353cE1D0591563Fc3Bb4
// Strategy [Aave v3 cbBTC/yvUSD Lender Borrower]: 0x7D3536382805f01b3c8c88a9a2037466C1FEd424
// Strategy [Aave v3 cbBTC/ysPYUSD Lender Borrower]: 0x3a36da4424906752c97532619757E232f4970a0f
// Strategy [Aave v3 cbBTC/ysRLUSD Lender Borrower]: 0xCba881a129A8Fe951c5909bDeCe34184B06eCafB
// Strategy [Aave v3 cbBTC/ysUSDT Lender Borrower]: 0x64D67F70Fa1a6898485D69b5916E1ce1e494B026
// Exchange: 0xEbb2908D09eCf29924CfB0dFa28687491EcdEaF0
// Oracle: 0x804916A943A01E2E82304C1C0E743eAeF63D2FFd