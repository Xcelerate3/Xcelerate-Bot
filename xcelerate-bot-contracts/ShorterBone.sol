// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./libraries/AllyLibrary.sol";
import "./interfaces/governance/IIpistrToken.sol";
import "./interfaces/ISRC20.sol";
import "./interfaces/IUSDT.sol";
import "./interfaces/IShorterBone.sol";
import "./interfaces/v1/IPoolGuardian.sol";
import "./interfaces/v1/ITradingHub.sol";
import "./criteria/ChainSchema.sol";
import "./util/BoringMath.sol";

/// @notice Mainstay for all smart contracts
contract ShorterBone is ChainSchema, IShorterBone {
    using SafeToken for ISRC20;
    using BoringMath for uint256;

    struct TokenInfo {
        bool inWhiteList;
        address swapRouter;
        uint256 tokenRatingScore;
    }

    bool internal mintable;
    uint256 public totalTokenSize;
    address public override TetherToken;

    /// @notice Ally contract and corresponding verified id
    mapping(bytes32 => address) public allyContracts;
    mapping(address => TokenInfo) public override getTokenInfo;
    mapping(uint256 => address) public tokens;
    mapping(address => bool) public taxFreeTokenList;

    constructor(address _SAVIOR) public ChainSchema(_SAVIOR) {
        mintable = true;
    }

    modifier onlyAlly(bytes32 allyId) {
        require(msg.sender == allyContracts[allyId], "ShorterBone: Caller is not the ally");
        _;
    }

    /// @notice Move the token from user to ally contracts, restricted to be called by the ally contract self
    function tillIn(
        address tokenAddr,
        address caller,
        bytes32 toAllyId,
        uint256 amount
    ) external override whenNotPaused onlyAlly(toAllyId) {
        if (amount == 0) return;
        _transfer(tokenAddr, caller, allyContracts[toAllyId], amount);
        emit TillIn(toAllyId, caller, tokenAddr, amount);
    }

    /// @notice Move the token from an ally contract to user, restricted to be called by the ally contract
    function tillOut(
        address tokenAddr,
        bytes32 fromAllyId,
        address caller,
        uint256 amount
    ) external override whenNotPaused onlyAlly(fromAllyId) {
        if (amount == 0) return;
        _transfer(tokenAddr, allyContracts[fromAllyId], caller, amount);
        emit TillOut(fromAllyId, caller, tokenAddr, amount);
    }

    function poolTillIn(
        uint256 poolId,
        address token,
        address user,
        uint256 amount
    ) external override whenNotPaused {
        if (amount == 0) return;
        address poolAddr = _getPoolAddr(poolId);
        require(msg.sender == poolAddr, "ShorterBone: Caller is not a Pool");
        _transfer(token, user, poolAddr, amount);
        emit PoolTillIn(poolId, user, amount);
    }

    function poolTillOut(
        uint256 poolId,
        address token,
        address user,
        uint256 amount
    ) external override whenNotPaused {
        if (amount == 0) return;
        address poolAddr = _getPoolAddr(poolId);
        require(msg.sender == poolAddr, "ShorterBone: Caller is not a Pool");
        _transfer(token, poolAddr, user, amount);
        emit PoolTillOut(poolId, user, amount);
    }

    function poolRevenue(
        uint256 poolId,
        address user,
        address token,
        uint256 amount,
        IncomeType _type
    ) external override whenNotPaused {
        if (amount == 0) return;
        address poolAddr = _getPoolAddr(poolId);
        require(msg.sender == poolAddr, "ShorterBone: Caller is not a Pool");
        _transfer(token, poolAddr, allyContracts[AllyLibrary.TREASURY], amount);
        emit Revenue(token, user, amount, _type);
    }

    function revenue(
        address tokenAddr,
        address from,
        uint256 amount,
        IncomeType _type
    ) external override whenNotPaused onlyAlly(AllyLibrary.COMMITTEE) {
        if (amount == 0) return;
        address treasuryAddr = allyContracts[AllyLibrary.TREASURY];
        _transfer(tokenAddr, from, treasuryAddr, amount);
        emit Revenue(tokenAddr, from, amount, _type);
    }

    function _getPoolAddr(uint256 poolId) internal view returns (address strPoolAddr) {
        address poolGuardian = allyContracts[AllyLibrary.POOL_GUARDIAN];
        (, strPoolAddr, ) = IPoolGuardian(poolGuardian).getPoolInfo(poolId);
    }

    function mintByAlly(
        bytes32 sendAllyId,
        address user,
        uint256 amount
    ) external override whenNotPaused onlyAlly(sendAllyId) {
        if (amount == 0) return;
        require(mintable, "ShorterBone: Mint is unavailable for now");
        _mint(user, amount);
    }

    function getAddress(bytes32 allyId) external view override returns (address) {
        address res = allyContracts[allyId];
        require(res != address(0), "ShorterBone: AllyId not found");
        return res;
    }

    function setAlly(bytes32 allyId, address contractAddr) external isSavior {
        allyContracts[allyId] = contractAddr;
        emit ResetAlly(allyId, contractAddr);
    }

    function slayAlly(bytes32 allyId) external isSavior {
        delete allyContracts[allyId];
        emit AllyKilled(allyId);
    }

    function setTetherToken(address _TetherToken) external isSavior {
        require(_TetherToken != address(0), "ShorterBone: TetherToken is zero address");
        TetherToken = _TetherToken;
    }

    /// @notice Tweak the mint flag
    function setMintState(bool _flag) external isKeeper {
        mintable = _flag;
    }

    function addTokenWhiteList(
        address _swapRouter,
        address[] calldata tokenAddrs,
        uint256[] calldata _tokenRatingScores
    ) external isKeeper {
        require(tokenAddrs.length == _tokenRatingScores.length, "ShorterBone: Invaild params");
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            tokens[totalTokenSize++] = tokenAddrs[i];
            getTokenInfo[tokenAddrs[i]] = TokenInfo({inWhiteList: true, swapRouter: _swapRouter, tokenRatingScore: _tokenRatingScores[i]});
        }
    }

    function setTokenInWhiteList(address token, bool flag) external isKeeper {
        getTokenInfo[token].inWhiteList = flag;
    }

    function setTokenSwapRouter(address token, address newSwapRouter) external isKeeper {
        getTokenInfo[token].swapRouter = newSwapRouter;
    }

    function setTokenRatingScore(address token, uint256 tokenRatingScore) external onlyAlly(AllyLibrary.COMMITTEE) {
        getTokenInfo[token].tokenRatingScore = tokenRatingScore;
    }

    function setTaxFreeTokenList(address[] calldata tokenAddrs, bool flag) external isKeeper {
        for (uint256 i = 0; i < tokenAddrs.length; i++) {
            taxFreeTokenList[tokenAddrs[i]] = flag;
        }
    }

    function _transfer(
        address tokenAddr,
        address from,
        address to,
        uint256 value
    ) internal {
        ISRC20 token = ISRC20(tokenAddr);
        require(token.allowance(from, address(this)) >= value, "ShorterBone: Amount exceeded the limit");
        uint256 token0Bal = token.balanceOf(from);
        uint256 token1Bal = token.balanceOf(to);

        if (tokenAddr == TetherToken) {
            IUSDT(tokenAddr).transferFrom(from, to, value);
        } else {
            token.safeTransferFrom(from, to, value);
        }

        uint256 token0Aft = token.balanceOf(from);
        uint256 token1Aft = token.balanceOf(to);

        if (!taxFreeTokenList[tokenAddr] && (token0Aft.add(value) != token0Bal || token1Bal.add(value) != token1Aft)) {
            revert("ShorterBone: Fatal exception. transfer failed");
        }
    }

    function _mint(address user, uint256 amount) internal {
        address ipistrAddr = allyContracts[AllyLibrary.IPI_STR];
        require(ipistrAddr != address(0), "ShorterBone: IPISTR unavailable");

        IIpistrToken(ipistrAddr).mint(user, amount);
    }
}
