// SPDX-License-Identifier: GPL-3.0
// Docgen-SOLC: 0.8.15

pragma solidity ^0.8.15;
import "../interfaces/IContractRegistry.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 *  @notice Provides an internal `_getContract` helper function to access the `ContractRegistry` - Upgradable version
 */
abstract contract ContractRegistryAccessUpgradeable is Initializable {
  IContractRegistry internal _contractRegistry;

  function __ContractRegistryAccess_init(IContractRegistry contractRegistry_) internal onlyInitializing {
    require(address(contractRegistry_) != address(0), "Zero address");
    require(address(_contractRegistry) == address(0), "already set");
    _contractRegistry = contractRegistry_;
  }

  /**
   *  @notice Get a contract address by bytes32 name
   *  @param _name bytes32 contract name
   *  @dev contract name should be a keccak256 hash of the name string, e.g. `keccak256("ContractName")`
   *  @return contract address
   */
  function _getContract(bytes32 _name) internal view virtual returns (address) {
    return _contractRegistry.getContract(_name);
  }

  /**
   *  @notice Get contract id from contract address.
   *  @param _contractAddress contract address
   *  @return name - keccak256 hash of the name string  e.g. `keccak256("ContractName")`
   */
  function _getContractIdFromAddress(address _contractAddress) internal view virtual returns (bytes32) {
    return _contractRegistry.getContractIdFromAddress(_contractAddress);
  }
}
