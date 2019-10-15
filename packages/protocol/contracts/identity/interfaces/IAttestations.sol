pragma solidity ^0.5.3;


interface IAttestations {

  function initialize(address, uint256, address[] calldata, uint256[] calldata) external;

  function setAttestationRequestFee(address, uint256) external;
  function request(bytes32, uint256, address) external;
  function selectIssuers(bytes32) external;
  function reveal(bytes32, bytes calldata, address, bool) external;
  function complete(bytes32, uint8, bytes32, bytes32) external;
  function revoke(bytes32, uint256) external;
  function withdraw(address) external;

  function setAttestationExpiryBlocks(uint256) external;

  function setAccountDataEncryptionKey(bytes calldata) external;
  function authorizeAttestor(address, uint8, bytes32, bytes32) external;
  function setMetadataURL(string calldata) external;
  function setWalletAddress(address) external;
  function setAccount(bytes calldata, address) external;

  function getAttestorFromAccount(address) external view returns (address);
  function getAccountFromAttestor(address) external view returns (address);

  function getDataEncryptionKey(address) external view returns (bytes memory);
  function getWalletAddress(address) external view returns (address);
  function getMetadataURL(address) external view returns (string memory);

  function getActiveAttestationRequest(bytes32, address) external view returns (uint128, uint128);
  function getAttestationRequestFee(address) external view returns (uint256);

  function lookupAccountsForIdentifier(bytes32) external view returns (address[] memory);

  function getAttestationStats(
    bytes32,
    address
  )
    external
    view
    returns (uint32, uint32);

  function getAttestationState(
    bytes32,
    address,
    address
  )
    external
    view
    returns (uint8, uint128);

  function getAttestationRequestFeeToken(address) external view returns (address);
  function getMostRecentAttestationRequest(address) external view returns (uint256);
}
