// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import {AaveLenderBorrowerStrategy as Strategy, ERC20} from "./Strategy.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract StrategyFactory {

    event NewStrategy(address indexed strategy, address indexed asset);

    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track the deployments. asset => pool => strategy
    mapping(address => address) public deployments;

    constructor(address _management, address _performanceFeeRecipient, address _keeper, address _emergencyAdmin) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    /**
     * @notice Deploy a new Strategy.
     * @param _asset The underlying asset for the strategy to use.
     * @param _name The name of the strategy.
     * @param _lenderVault The address of the lender vault that the strategy will use.
     * @param _addressesProvider The address of the Aave addresses provider.
     * @param _exchange The exchange contract for buying/selling borrow token.
     * @param _categoryId The eMode category ID to use for this strategy.
     * @return . The address of the new strategy.
     */
    function newStrategy(
        address _asset,
        string calldata _name,
        address _lenderVault,
        address _addressesProvider,
        address _exchange,
        uint8 _categoryId
    ) external virtual returns (address) {
        // tokenized strategies available setters.
        IStrategyInterface _newStrategy = IStrategyInterface(
            address(new Strategy(_asset, _name, _lenderVault, _addressesProvider, _exchange, _categoryId))
        );

        _newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        _newStrategy.setKeeper(keeper);

        _newStrategy.setPendingManagement(management);

        _newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewStrategy(address(_newStrategy), _asset);

        deployments[_asset] = address(_newStrategy);
        return address(_newStrategy);
    }

    function setAddresses(address _management, address _performanceFeeRecipient, address _keeper) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return deployments[_asset] == _strategy;
    }

}
