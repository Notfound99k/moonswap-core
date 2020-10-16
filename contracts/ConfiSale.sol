pragma solidity =0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./Pauseable.sol";
import './SponsorWhitelistControl.sol';
import './libraries/Math.sol';
import './interfaces/IERC1155TokenReceiver.sol';
import './interfaces/IConfiNFT.sol';


contract ConfiSale is Ownable, Pauseable, IERC777Recipient, IERC1155TokenReceiver{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    SponsorWhitelistControl constant public SPONSOR = SponsorWhitelistControl(address(0x0888000000000000000000000000000000000001));
    IERC1820Registry private _erc1820 = IERC1820Registry(0x866aCA87FF33a0ae05D2164B3D999A804F583222);
    // keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
      0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    mapping(uint256 => bool) public confiStls; // confi tokenId status list
    uint256[] public confiIds; // confi tokenId list
    uint256 public confiSupply;
    address public confi;
    uint256 public multipleCategoryId;
    uint256 public multiple;
    address public cMoonToken;

    struct UserInfo {
      uint256 weight; // calc weight
      uint256 rewardDebt;
      uint256 balance;
      uint256 number; //user stake number
    }

    // userAddr => catId =>
    mapping(address => mapping(uint256 => uint256)) public userStakeCounts;
    mapping(address => mapping(uint256 => uint256[])) public userStakeConfi;
    // from 1 start
    mapping(address => mapping(uint256 => uint256)) userConfiIndexes;
    mapping(uint256 => uint256) public confiCategories; // tokenId => catId
    mapping(address => uint256) public userLatestBuy;

    mapping(address => UserInfo) public userInfo;
    // calc reward
    uint256 public totalWeight;
    uint256 public totalNumber; // total stake number
    uint256 public accTokenPerShare;
    uint256 public lastRewardBlock;
    uint256 public intervalBlock; // reward interval block num
    // buy stage
    struct Stage {
      uint256 stageNo;
      uint256 total;
      uint256 balance;
      bool isOpen;
      uint256 price;
    }
    mapping(uint256 => Stage) public stages;

    uint256 public stageNo;
    uint256 public totalPoolAmount;
    uint256 public poolBalance;
    uint256 public totalDevAmount;
    uint256 public devBalance;
    address public devAddr;
    uint256 public rewardRatio;
    uint256 public apyRatio; // 0.01%
    bool public outEnable; // game end open harvest
    bool public stakeEnable; // game stake enable

    mapping (address => bool) private _accountCheck;
    address[] private _accountList;

    // event
    event TokenTransfer(address indexed tokenAddress, address indexed from, address to, uint256 value);
    event uploadNFTEvent(address indexed from, uint256 count);
    event TokenBuy(address indexed from, address to, uint256 tokenId, uint256 value);
    event TokenStake(address indexed from, address to, uint256 tokenId);
    event TokenUnStake(address indexed from, address to, uint256 tokenId);

    constructor(
          address _confi,
          address _cMoonToken,
          address _devAddr
      ) public {
          confi = _confi;
          cMoonToken = _cMoonToken;
          devAddr = _devAddr;

          rewardRatio = 30; // 30% to pool reward
          multiple = 20;
          multipleCategoryId = 6;
          apyRatio = 3;
          intervalBlock = 120;

          outEnable = false;
          stakeEnable = true;

          _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

          // register all users as sponsees
          address[] memory users = new address[](1);
          users[0] = address(0);
          SPONSOR.add_privilege(users);
    }

    // functions
    // 0x7a280947
    function _uploadNFT(address _from, uint256[] memory _ids, uint256[] memory _amounts) internal {
      require(_ids.length == _amounts.length, "ConfiSale: INVALID_ARRAYS_LENGTH");
      uint256 range = _ids.length;

      for(uint256 i = 0; i < range; i ++){
        if(confiStls[_ids[i]]){
          continue;
        }
        if(confiIds.length > confiSupply){
          confiIds[confiSupply] = _ids[i];
        }else{
            confiIds.push(_ids[i]);
        }
        confiStls[_ids[i]] = true;
        confiSupply = confiSupply.add(1);
      }

      emit uploadNFTEvent(_from, range);
    }

    function confiIdsLength() external view returns(uint256) {
      return confiIds.length;
    }

    function setStageNo(uint256 _stageNo) external onlyOwner {
      stageNo = _stageNo;
    }

    function initStage(uint256 _stageNo, uint256 _total, bool _isOpen, uint256 _price) external onlyOwner {
        Stage storage _stage = stages[_stageNo];
        require(_stage.stageNo == 0, "ConfiSale: stageNo exists");
        stages[_stageNo] = Stage({
            stageNo: _stageNo,
            total: _total,
            balance: _total,
            isOpen: _isOpen,
            price: _price
        });
    }

    function setMultiple(uint256 _catId, uint256 _multiple) external onlyOwner {
        require(_catId > 0, "ConfiSale: catId is zero");
        multipleCategoryId = _catId;
        multiple = _multiple;
    }

    function updateTotal(uint256 _stageNo, uint256 _count, bool isAdd) external onlyOwner {
      Stage storage _stage = stages[_stageNo];
      require(_stage.stageNo > 0, "ConfiSale: stageNo not exists");
      if(isAdd){
        _stage.total = _stage.total.add(_count);
        _stage.balance = _stage.balance.add(_count);
      }else{
        _stage.total = _stage.total.sub(_count);
        _stage.balance = _stage.balance.sub(_count);
      }
    }

    function updatePrice(uint256 _stageNo, uint256 _price) external onlyOwner {
      Stage storage _stage = stages[_stageNo];
      require(_stage.stageNo > 0, "ConfiSale: stageNo not exists");
      _stage.price = _price;
    }

    function setIsOpen(uint256 _stageNo, bool _isOpen) external onlyOwner {
      Stage storage _stage = stages[_stageNo];
      require(_stage.stageNo > 0, "ConfiSale: stageNo not exists");
      _stage.isOpen = _isOpen;
    }

    function setRewardRatio(uint256 _rewardRatio) external onlyOwner {
        _poolLogic();
        rewardRatio = _rewardRatio;
    }

    function setApyRatio(uint256 _apyRatio) external onlyOwner {
        _poolLogic();
        apyRatio = _apyRatio;
    }

    // user
    function _buy(address _from, uint256 _amount) internal {
      require(stageNo > 0, "ConfiSale: no stage start");
      Stage storage _stage = stages[stageNo];
      require(_stage.stageNo > 0, "ConfiSale: stageNo not exists");
      require(_stage.price == _amount, "ConfiSale: pay amount is invalid");
      require(_stage.isOpen, "ConfiSale: stage no open");
      require(_stage.balance > 0, "ConfiSale: balance is no enough");
      require(confiSupply > 0, "ConfiSale: nft supply no enough");

      _poolLogic();
      _stage.balance = _stage.balance.sub(1);
      // random assign tokenId`
      uint256 _index = _seed(_from, confiSupply);
      uint256 _tokenId = confiIds[_index];
      confiIds[_index] = confiIds[confiSupply - 1];
      delete confiIds[confiSupply - 1];
      confiSupply = confiSupply.sub(1);
      _poolAssign(_amount);
      _safeNFTTransfer(_from, _tokenId);

      userLatestBuy[_from] = _tokenId;
      emit TokenBuy(address(this), _from, _tokenId, _amount);
    }

    function unstakeById(uint256 _id) external whenPaused {
        uint256 _catId = _getCatId(_id);
        uint256 _stakeCount = userStakeCounts[msg.sender][_catId];
        require(_id > 0, "ConfiSale: unstake id invalid");
        require(_stakeCount > 0, "ConfiSale: no confi");
        require(userConfiIndexes[msg.sender][_id] > 0, "ConfiSale: no stake");
        _poolLogic();
        uint256 _weight = _getMultiple(_catId);
        UserInfo storage user = userInfo[msg.sender];
        uint256 pending = user.weight.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
        user.balance = user.balance.add(pending);

        // From the back forward
        user.weight = user.weight.sub(_weight);
        user.number = user.number.sub(1);
        totalWeight = totalWeight.sub(_weight);
        totalNumber = totalNumber.sub(1);
        user.rewardDebt = user.weight.mul(accTokenPerShare).div(1e12);
        userStakeCounts[msg.sender][_catId] = userStakeCounts[msg.sender][_catId].sub(1);

        uint256 _posIndex = userConfiIndexes[msg.sender][_id];
        require(_id == userStakeConfi[msg.sender][_catId][_posIndex - 1], "ConfiSale: invalid TokenId");
        if(_posIndex == _stakeCount){
          delete userStakeConfi[msg.sender][_catId][_stakeCount - 1];
        }else{
          userStakeConfi[msg.sender][_catId][_posIndex - 1] = userStakeConfi[msg.sender][_catId][_stakeCount - 1];
          delete userStakeConfi[msg.sender][_catId][_stakeCount - 1];
          userConfiIndexes[msg.sender][userStakeConfi[msg.sender][_catId][_posIndex - 1]] = _posIndex;
        }

        _safeNFTTransfer(msg.sender, _id);

        emit TokenUnStake(address(this), msg.sender, _id);
    }

    function uploadConfiCategory(uint256[] calldata _ids) external onlyOwner {

      uint256 range = _ids.length;
      for(uint256 i = 0; i < range; i ++){
        uint256 _catId = _getCatId(_ids[i]);
        confiCategories[_ids[i]] = _catId;
        confiStls[_ids[i]] = true;
      }
    }

    //  stake
    function _stake(address _from, uint256[] memory _ids, uint256[] memory _amounts) internal {
        require(_ids.length == _amounts.length, "ConfiSale: INVALID_ARRAYS_LENGTH");
        require(totalPoolAmount > 0, "ConfiSale: on start");
        require(stakeEnable, "ConfiSale: stake no start");
        uint256 range = _ids.length;
        UserInfo storage user = userInfo[_from];
        _poolLogic();
        // harvest
        if(user.weight > 0){
          uint256 pending = user.weight.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
          user.balance = user.balance.add(pending);
        }

        require(user.number.add(_ids.length) < 500, "ConfiSale: max is overflow");

        // stake
        for(uint256 i = 0; i < range; i ++){
            if(!confiStls[_ids[i]]){
              revert("ConfiSale: no sale confi");
            }
            uint256 _catId = confiCategories[_ids[i]];
            if(_catId == 0){
               revert("ConfiSale: no cat setting");
            }

            uint256 _weight = _getMultiple(_catId);

            if(userStakeConfi[_from][_catId].length > userStakeCounts[_from][_catId]){
                userStakeConfi[_from][_catId][userStakeCounts[_from][_catId]] = _ids[i];
            }else{
              userStakeConfi[_from][_catId].push(_ids[i]);
            }

            userConfiIndexes[_from][_ids[i]] = userStakeCounts[_from][_catId].add(1);
            userStakeCounts[_from][_catId] = userStakeCounts[_from][_catId].add(1);
            user.weight = user.weight.add(_weight);
            totalWeight = totalWeight.add(_weight);
            user.number = user.number.add(1);
            totalNumber = totalNumber.add(1);

            emit TokenStake(_from, address(this), _ids[i]);
        }
        // cacl deposit part
        user.rewardDebt = user.weight.mul(accTokenPerShare).div(1e12);

        // data migration
        if (!_accountCheck[_from]) {
            _accountCheck[_from] = true;
            _accountList.push(_from);
        }
    }

    function _getMultiple(uint256 _catId) internal view returns(uint256) {
        if(_catId == multipleCategoryId){
          return multiple;
        }else{
          return 1;
        }
    }


    function _getCatId(uint256 _id) internal view returns(uint256){
      uint256 _catId = IConfiNFT(confi).categoryOf(_id);
      return _catId;
    }

    function harvest() external whenPaused {
      UserInfo storage user = userInfo[msg.sender];
      require(user.weight > 0, "ConfiSale: weight is zero");
      require(outEnable, "confiSale: outEnable is closed");
      _poolLogic();
      uint256 pending = user.weight.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
      pending = user.balance.add(pending);
      user.rewardDebt = user.weight.mul(accTokenPerShare).div(1e12);
      user.balance = 0;
      poolBalance = poolBalance.sub(pending);
      if(pending > 0){
        _safeTokenTransfer(msg.sender, pending);
      }
    }

    function devWithdraw(uint256 _amount) external {
      require(_amount <= devBalance, "confiSale: balance insufficient");
      devBalance = devBalance.sub(_amount);
      _safeTokenTransfer(devAddr, _amount);
    }

    function pendingToken(address _user) external view returns(uint256) {
      UserInfo storage user = userInfo[_user];
      uint256 _accTokenPerShare = accTokenPerShare;
      if (block.number > lastRewardBlock && totalWeight > 0) {
          uint256 shareReward = poolBalance
              .mul(block.number.sub(lastRewardBlock).div(intervalBlock))
              .mul(apyRatio)
              .div(10000);

          _accTokenPerShare = _accTokenPerShare.add(shareReward.mul(1e12).div(totalWeight));
      }

      uint256 pending = user.weight.mul(_accTokenPerShare).div(1e12).sub(user.rewardDebt);
      return user.balance.add(pending);
    }

    // limit confi token
    function retrieve(address _to, uint256 _count) external onlyOwner {
      if(_count > confiSupply) {
        _count = confiSupply;
      }

      for(uint256 i = 1; i <= _count; i ++){
          uint256 _tokenId = confiIds[confiSupply - 1];
          confiStls[_tokenId] = false;
          delete confiIds[confiSupply - 1];
          confiSupply = confiSupply.sub(1);
          _safeNFTTransfer(_to, _tokenId);
      }
    }

    function forceRetrieve(address _to, uint256 _tokenId) external onlyOwner{
        if(confiSupply > 0){
          confiSupply = confiSupply.sub(1);
        }
        confiStls[_tokenId] = false;
        _safeNFTTransfer(_to, _tokenId);
    }

    function _poolLogic() internal {
      if(poolBalance == 0){
        lastRewardBlock = block.number;
        return;
      }
      if(intervalBlock == 0){
        return;
      }
      if(intervalBlock > block.number){
        return;
      }
      if(block.number.sub(intervalBlock) <= lastRewardBlock){
        return;
      }
      if(totalWeight == 0){
        lastRewardBlock = block.number;
        return;
      }

      uint256 _times = block.number.sub(lastRewardBlock).div(intervalBlock);
      uint256 shareReward = poolBalance
            .mul(_times)
            .mul(apyRatio)
            .div(10000);
      poolBalance = poolBalance.sub(shareReward);
      accTokenPerShare = accTokenPerShare.add(shareReward.mul(1e12).div(totalWeight));
      lastRewardBlock = lastRewardBlock.add(intervalBlock.mul(_times));
    }

    function _poolAssign(uint256 _amount) internal {
      require(devAddr != address(0), "ConfiSale: devAddr is zero address");
      uint256 _reward = _amount.mul(rewardRatio).div(100);
      totalPoolAmount = totalPoolAmount.add(_reward);
      poolBalance = poolBalance.add(_reward);
      totalDevAmount = totalDevAmount.add(_amount.sub(_reward));
      devBalance = devBalance.add(_amount.sub(_reward));
    }

    function _seed(address _user, uint256 _confiSupply) public view returns (uint256) {
        return uint256(
            uint256(keccak256(abi.encodePacked(_user, block.number, block.timestamp, block.difficulty))) % _confiSupply
        );
    }

    function _safeNFTTransfer(address _to, uint256 _id) internal {
        IConfiNFT(confi).safeTransferFrom(address(this), _to, _id, 1, '');
    }

    function _safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = IERC20(cMoonToken).balanceOf(address(this));
        require(_amount <= tokenBal, "ConfiSale: cMoon insufficient");
        IERC20(cMoonToken).transfer(_to, _amount);
    }

    function onERC1155Received(
          address _operator,
          address _from,
          uint256 _id,
          uint256 _amount,
          bytes calldata _data) external returns(bytes4){

          require(msg.sender == confi, "ConfiSale: only receive confi");
          uint256[] memory _ids;
          _ids[0] = _id;
          uint256[] memory _amounts;
          _amounts[0] = _amount;
          if(_data[0] == 0x01) {
            //
            _uploadNFT(_from, _ids, _amounts);
          }else{
            _stake(_from, _ids, _amounts);
          }

          return 0xf23a6e61;
    }

    function onERC1155BatchReceived(
          address _operator,
          address _from,
          uint256[] calldata _ids,
          uint256[] calldata _amounts,
          bytes calldata _data) external returns(bytes4){

          require(msg.sender == confi, "ConfiSale: only receive confi");
          if(_data[0] == 0x01) {
            // uploadNFT
            _uploadNFT(_from, _ids, _amounts);
          }else{
            // stake
            _stake(_from, _ids, _amounts);
          }

          return 0xbc197c81;
    }

    // erc777 receiveToken
    function tokensReceived(address operator, address from, address to, uint amount,
          bytes calldata userData,
          bytes calldata operatorData) external {

          require(msg.sender == cMoonToken, "ConfiSale: only receive cMoon");
          _buy(from, amount);
          emit TokenTransfer(msg.sender, from, to, amount);
    }

    function setDevAddr(address _devAddr) external onlyOwner {
        devAddr = _devAddr;
    }

    function setOutEnable(bool _outEnable) external onlyOwner {
       outEnable = _outEnable;
    }

    function setStakeEnable(bool _stakeEnable) external onlyOwner {
       stakeEnable = _stakeEnable;
    }

    //---------------- Data Migration ----------------------
    function accountTotal() public view returns (uint256) {
       return _accountList.length;
    }

    function accountList(uint256 begin) public view returns (address[100] memory) {
        require(begin >= 0 && begin < _accountList.length, "MoonSwap: accountList out of range");
        address[100] memory res;
        uint256 range = Math.min(_accountList.length, begin.add(100));
        for (uint256 i = begin; i < range; i++) {
            res[i-begin] = _accountList[i];
        }
        return res;
    }
}
