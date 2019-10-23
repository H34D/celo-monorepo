pragma solidity ^0.5.3;

import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./interfaces/IAccounts.sol";

import "../common/Initializable.sol";
import "../common/Signatures.sol";
import "../common/UsingRegistry.sol";

contract Accounts is IAccounts, ReentrancyGuard, Initializable, UsingRegistry {

  using SafeMath for uint256;

  struct Signers {
    // The address that is authorized to sign a vote on behalf of the account.
    // The account can vote as well, whether or not an vote signing key has been specified.
    address voting;
    // The address that is authorized to sign consensus messages on behalf of the account.
    // The account can manage the validator, whether or not an validation signing key has been
    // specified. However if an validation signing key has been specified, only that key may
    // actually participate in consensus.
    address validating;

    // The address of the key with which this account wants to sign attestations on the Attestations
    // contract
    address attesting;
  }

  struct Account {
    bool exists;
    // Each account may authorize signing keys to use for voting, valdiating or attestation.
    // These keys may not be keys of other accounts, and may not be authorized by any other
    // account for any purpose.
    Signers signers;

    // The address at which the account expects to receive transfers
    address walletAddress;

    // The ECDSA public key used to encrypt and decrypt data for this account
    bytes dataEncryptionKey;

    // The URL under which an account adds metadata and claims
    string metadataURL;
  }

  mapping(address => Account) private accounts;

  // Maps voting and validating keys to the account that provided the authorization.
  mapping(address => address) public authorizedBy;


  event AttestationSignerAuthorized(address indexed account, address signer);
  event VoteSignerAuthorized(address indexed account, address signer);
  event ValidationSignerAuthorized(address indexed account, address signer);

  event AccountDataEncryptionKeySet(
    address indexed account,
    bytes dataEncryptionKey
  );

  event AccountMetadataURLSet(
    address indexed account,
    string metadataURL
  );

  event AccountWalletAddressSet(
    address indexed account,
    address walletAddress
  );

  function initialize() external initializer {
    _transferOwnership(msg.sender);
  }

  /**
   * @notice Creates an account.
   * @return True if account creation succeeded.
   */
  function createAccount() external returns (bool) {
    require(isNotAccount(msg.sender) && isNotAuthorized(msg.sender));
    Account storage account = accounts[msg.sender];
    account.exists = true;
    return true;
  }

  /**
   * @notice Convenience Setter for the dataEncryptionKey and wallet address for an account
   * @param dataEncryptionKey secp256k1 public key for data encryption. Preferably compressed.
   * @param walletAddress The wallet address to set for the account
   */
  function setAccount(
    bytes calldata dataEncryptionKey,
    address walletAddress
  )
    external
  {
    setAccountDataEncryptionKey(dataEncryptionKey);
    setWalletAddress(walletAddress);
  }

  /**
   * @notice Authorizes an address to sign votes on behalf of the account.
   * @param voter The address of the vote signing key to authorize.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev v, r, s constitute `voter`'s signature on `msg.sender`.
   */
  function authorizeVoteSigner(
    address voter,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external
    nonReentrant
  {
    Account storage account = accounts[msg.sender];
    authorize(voter, account.signers.voting, v, r, s);
    account.signers.voting = voter;
    emit VoteSignerAuthorized(msg.sender, voter);
  }

  /**
   * @notice Authorizes an address to sign consensus messages on behalf of the account.
   * @param validator The address of the signing key to authorize.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev v, r, s constitute `validator`'s signature on `msg.sender`.
   */
  function authorizeValidationSigner(
    address validator,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    external
    nonReentrant
  {
    Account storage account = accounts[msg.sender];
    authorize(validator, account.signers.validating, v, r, s);
    account.signers.validating = validator;
    emit ValidationSignerAuthorized(msg.sender, validator);
  }

  /**
   * @notice Authorizes an address to sign attestations on behalf of the account.
   * @param attestor The address of the signing key to authorize.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev v, r, s constitute `attestor`'s signature on `msg.sender`.
   */
  function authorizeAttestationSigner(
    address attestor,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    public
  {
    Account storage account = accounts[msg.sender];
    authorize(attestor, account.signers.attesting, v, r, s);
    account.signers.attesting = attestor;
    emit AttestationSignerAuthorized(msg.sender, attestor);
  }

  /**
   * @notice Returns the account associated with `accountOrAttestationSigner`.
   * @param accountOrAttestationSigner The address of the account or authorized attestation
   *                                   signing key.
   * @dev Fails if the `accountOrAttestationSigner` is not an account or authorized attestation
   *      signing key.
   * @return The associated account.
   */
  function getAccountFromAttestationSigner(address accountOrAttestationSigner)
    public
    view
    returns (address)
  {
    address authorizingAccount = authorizedBy[accountOrAttestationSigner];
    if (authorizingAccount != address(0)) {
      require(accounts[authorizingAccount].signers.attesting == accountOrAttestationSigner);
      return authorizingAccount;
    } else {
      require(isAccount(accountOrAttestationSigner));
      return accountOrAttestationSigner;
    }
  }

  /**
   * @notice Returns the account associated with `accountOrVoteSigner`.
   * @param accountOrVoteSigner The address of the account or authorized voter.
   * @dev Fails if the `accountOrVoteSigner` is not an account or authorized voter.
   * @return The associated account.
   */
  function getAccountFromVoteSigner(address accountOrVoteSigner) external view returns (address) {
    address authorizingAccount = authorizedBy[accountOrVoteSigner];
    if (authorizingAccount != address(0)) {
      require(accounts[authorizingAccount].signers.voting == accountOrVoteSigner);
      return authorizingAccount;
    } else {
      require(isAccount(accountOrVoteSigner));
      return accountOrVoteSigner;
    }
  }

  /**
   * @notice Returns the account associated with `accountOrValidationSigner`.
   * @param accountOrValidationSigner The address of the account or authorized validator.
   * @dev Fails if the `accountOrValidationSigner` is not an account or authorized validator.
   * @return The associated account.
   */
  function getAccountFromValidationSigner(address accountOrValidationSigner)
    public
    view
    returns (address)
  {
    address authorizingAccount = authorizedBy[accountOrValidationSigner];
    if (authorizingAccount != address(0)) {
      require(accounts[authorizingAccount].signers.validating == accountOrValidationSigner);
      return authorizingAccount;
    } else {
      require(isAccount(accountOrValidationSigner));
      return accountOrValidationSigner;
    }
  }

  /**
   * @notice Returns the vote signer for the specified account.
   * @param account The address of the account.
   * @return The address with which the account can sign votes.
   */
  function getVoteSignerFromAccount(address account) public view returns (address) {
    require(isAccount(account));
    address voter = accounts[account].signers.voting;
    return voter == address(0) ? account : voter;
  }

  /**
   * @notice Returns the validation signer for the specified account.
   * @param account The address of the account.
   * @return The address with which the account can register a validator or group.
   */
  function getValidationSignerFromAccount(address account) public view returns (address) {
    require(isAccount(account));
    address validator = accounts[account].signers.validating;
    return validator == address(0) ? account : validator;
  }

  /**
   * @notice Returns the attestation signer for the specified account.
   * @param account The address of the account.
   * @return The address with which the account can sign attestations.
   */
  function getAttestationSignerFromAccount(address account) public view returns (address) {
    require(isAccount(account));
    address attestor = accounts[account].signers.attesting;
    return attestor == address(0) ? account : attestor;
  }

    /**
   * @notice Authorizes voting or validating power of `msg.sender`'s account to another address.
   * @param current The address to authorize.
   * @param previous The previous authorized address.
   * @param v The recovery id of the incoming ECDSA signature.
   * @param r Output value r of the ECDSA signature.
   * @param s Output value s of the ECDSA signature.
   * @dev Fails if the address is already authorized or is an account.
   * @dev v, r, s constitute `current`'s signature on `msg.sender`.
   */
  function authorize(
    address current,
    address previous,
    uint8 v,
    bytes32 r,
    bytes32 s
  )
    private
  {
    require(isAccount(msg.sender) && isNotAccount(current) && isNotAuthorized(current));

    address signer = Signatures.getSignerOfAddress(msg.sender, v, r, s);
    require(signer == current);

    authorizedBy[previous] = address(0);
    authorizedBy[current] = msg.sender;
  }

  /**
   * @notice Check if an account already exists.
   * @param account The address of the account
   * @return Returns `true` if account exists. Returns `false` otherwise.
   */
  function isAccount(address account) public view returns (bool) {
    return (accounts[account].exists);
  }

  /**
   * @notice Check if an account already exists.
   * @param account The address of the account
   * @return Returns `false` if account exists. Returns `true` otherwise.
   */
  function isNotAccount(address account) internal view returns (bool) {
    return (!accounts[account].exists);
  }

    /**
   * @notice Check if an address has been authorized by an account for voting or validating.
   * @param account The possibly authorized address.
   * @return Returns `true` if authorized. Returns `false` otherwise.
   */
  function isAuthorized(address account) external view returns (bool) {
    return (authorizedBy[account] != address(0));
  }

  /**
   * @notice Check if an address has been authorized by an account for voting or validating.
   * @param account The possibly authorized address.
   * @return Returns `false` if authorized. Returns `true` otherwise.
   */
  function isNotAuthorized(address account) internal view returns (bool) {
    return (authorizedBy[account] == address(0));
  }

  /**
   * @notice Setter for the metadata of an account.
   * @param metadataURL The URL to access the metadata.
   */
  function setMetadataURL(string calldata metadataURL) external {
    accounts[msg.sender].metadataURL = metadataURL;
    emit AccountMetadataURLSet(msg.sender, metadataURL);
  }

  /**
   * @notice Getter for the metadata of an account.
   * @param account The address of the account to get the metadata for.
   * @return metdataURL The URL to access the metadata.
   */
  function getMetadataURL(address account) external view returns (string memory) {
    return accounts[account].metadataURL;
  }

    /**
   * @notice Setter for the data encryption key and version.
   * @param dataEncryptionKey secp256k1 public key for data encryption. Preferably compressed.
   */
  function setAccountDataEncryptionKey(bytes memory dataEncryptionKey) public {
    require(dataEncryptionKey.length >= 33, "data encryption key length <= 32");
    accounts[msg.sender].dataEncryptionKey = dataEncryptionKey;
    emit AccountDataEncryptionKeySet(msg.sender, dataEncryptionKey);
  }

  /**
   * @notice Getter for the data encryption key and version.
   * @param account The address of the account to get the key for
   * @return dataEncryptionKey secp256k1 public key for data encryption. Preferably compressed.
   */
  function getDataEncryptionKey(address account) external view returns (bytes memory) {
    return accounts[account].dataEncryptionKey;
  }

  /**
   * @notice Setter for the wallet address for an account
   * @param walletAddress The wallet address to set for the account
   */
  function setWalletAddress(address walletAddress) public {
    accounts[msg.sender].walletAddress = walletAddress;
    emit AccountWalletAddressSet(msg.sender, walletAddress);
  }

  /**
   * @notice Getter for the wallet address for an account
   * @param account The address of the account to get the wallet address for
   * @return Wallet address
   */
  function getWalletAddress(address account) external view returns (address) {
    return accounts[account].walletAddress;
  }
}