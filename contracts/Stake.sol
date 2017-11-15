/**
  * stake users levs
  * get fee from trading contract
  * get eth from trading contract
  * calculate fee tokens to be generated
  * distribute fee tokens and lev to users in chunks.
  * re-purpose it for next trading duration.
  * what happens to extra fee if not enough trading happened? destroy it.
  * Stake will have full control over FEE.sol
  */
pragma solidity ^0.4.18;


import './SafeMath.sol';
import './Owned.sol';
import './Validating.sol';
import './Token.sol';
import './Fee.sol';


contract Stake is Owned, Validating {
  using SafeMath for uint;

  event StakeEvent(address indexed user, string indexed action, uint levs, uint startBlock, uint endBlock);

  // User address to (lev tokens)*(blocks left to end)
  mapping (address => uint) public levBlocks;

  // User address to lev tokens at stake
  mapping (address => uint) public stakes;

  uint public totalLevs;

  // Total lev blocks. this will be help not to iterate through full mapping
  uint public totalLevBlocks;

  // Wei for each Fee token
  uint public weiPerFee;

  // Total fee to be distributed
  uint public feeForTheStakingInterval;

  // Lev token reference
  Token public levToken; //revisit: is there a difference in storage versus using address?

  // FEE token reference
  Fee public feeToken; //revisit: is there a difference in storage versus using address?

  uint public startBlock;

  uint public endBlock;

  address public wallet;

  bool public feeCalculated = false;

  modifier isStaking {
    require(startBlock <= block.number && block.number < endBlock);
    _;
  }

  modifier isDoneStaking {
    require(block.number >= endBlock);
    _;
  }

  function() public payable {
    //        weiAsFee = weiAsFee.add(msg.value);
  }

  /// @notice Constructor to set all the default values for the owner, wallet,
  /// weiPerFee, tokenID and endBlock
  function Stake(
    address _owner,
    address _wallet,
    uint _weiPerFee,
    address _levToken
  ) public
    validAddress(_wallet)
    validAddress(_owner)
    validAddress(_levToken)
    notZero(_weiPerFee)
  {
    owner = _owner;
    wallet = _wallet;
    weiPerFee = _weiPerFee;
    levToken = Token(_levToken);
  }

  function version() external pure returns (string) {
    return "1.0.0";
  }

  /// @notice To set the the address of the LEV token
  /// @param _levToken The token address
  function setLevToken(address _levToken) external validAddress(_levToken) onlyOwner {
    levToken = Token(_levToken);
  }

  /// @notice To set the FEE token address
  /// @param _feeToken The address of that token
  function setFeeToken(address _feeToken) external validAddress(_feeToken) onlyOwner {
    feeToken = Fee(_feeToken);
  }

  /// @notice To set the wallet address by the owner only
  /// @param _wallet The wallet address
  function setWallet(address _wallet) external validAddress(_wallet) onlyOwner returns (bool) { //fixme: why the boolean?
    wallet = _wallet;
    return true;
  }

  /// @notice Public function to stake tokens executable by any user. The user
  /// has to approve the staking contract on token before calling this function.
  /// Refer to the tests for more information
  /// @param _quantity How many LEV tokens to lock for staking
  function stakeTokens(uint _quantity) external isStaking notZero(_quantity) returns (bool) { //fixme: why the boolean?
    require(levToken.balanceOf(msg.sender) >= _quantity);

    levBlocks[msg.sender] = levBlocks[msg.sender].add(_quantity.mul(endBlock.sub(block.number)));
    stakes[msg.sender] = stakes[msg.sender].add(_quantity);
    totalLevBlocks = totalLevBlocks.add(_quantity.mul(endBlock.sub(block.number)));
    totalLevs = totalLevs.add(_quantity);
    require(levToken.transferFrom(msg.sender, this, _quantity));
    StakeEvent(msg.sender, 'STAKED', _quantity, startBlock, endBlock);
    return true;
  }

  /// @notice To update the price of FEE tokens to the current value. Executable
  /// by the owner only
  function updateFeeForCurrentStakingInterval() external onlyOwner isDoneStaking returns (bool) { //fixme: why the boolean?
    require(feeCalculated == false);

    uint feeFromExchange = feeToken.balanceOf(this);
    feeForTheStakingInterval = feeFromExchange.add(this.balance.div(weiPerFee));
    feeCalculated = true;
    require(feeToken.burnTokens(feeFromExchange));
    wallet.transfer(this.balance);
    return true;
  }

  /// @notice To unlock and recover your LEV and FEE tokens after staking
  /// and fee to any user
  function redeemLevAndFee() external returns (bool) {
    return redeemLevAndFeeInternal(msg.sender);
  }

  function sendLevAndFeeToUsers(address[] _users) external onlyOwner returns (bool) { //fixme: why the boolean?
    for (uint i = 0; i < _users.length; i++) redeemLevAndFeeInternal(_users[i]);
    return true;
  }

  function redeemLevAndFeeInternal(address _user) //what does the Internal in the method name means?
    private //fixme: why internal? should be private (as there are no subclasses)
    validAddress(_user)
    isDoneStaking
    returns (bool) //fixme: why the boolean?
  {
    require(feeCalculated);
    require(totalLevBlocks > 0);

    uint levBlock = levBlocks[_user];
    uint stake = stakes[_user];
    require(stake > 0);

    uint feeEarned = levBlock.mul(feeForTheStakingInterval).div(totalLevBlocks);
    delete stakes[_user];
    delete levBlocks[_user];
    totalLevs = totalLevs.sub(stake);
    if (feeEarned > 0) require(feeToken.sendTokens(_user, feeEarned));
    require(levToken.transfer(_user, stake));

    StakeEvent(_user, 'CLAIMED', stake, startBlock, endBlock);
    return true;
  }

  /// @notice To start a new trading staking-interval where the price of the FEE will be updated
  /// @param _start The starting block.number of the new staking-interval
  /// @param _end When the new staking-interval ends in block.number
  function startNewStakingInterval(uint _start, uint _end)
    external
    notZero(_start)
    notZero(_end)
    onlyOwner
    isDoneStaking
    returns (bool)  //fixme: why the boolean?
  {
    require(totalLevs == 0);

    startBlock = _start;
    endBlock = _end;
    reset();
    return true;
  }

  function reset() private {
    totalLevBlocks = 0;
    feeForTheStakingInterval = 0;
    feeCalculated = false;
  }

}
