// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.6.12;

import {SafeERC20 as SafeToken} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../interfaces/ISRC20.sol";
import "../../util/BoringMath.sol";
import "../../util/Ownable.sol";
import "../../util/Pausable.sol";
import "../../util/Whitelistable.sol";
import "../../storage/WrappedTokenStorage.sol";

contract WrappedTokenImpl is Ownable, Pausable, Whitelistable, WrappedTokenStorage {
    using BoringMath for uint256;
    using SafeToken for ISRC20;

    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     */
    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    function transfer(address to, uint256 value) external whenNotPaused inWhitelist(msg.sender) inWhitelist(to) returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external whenNotPaused inWhitelist(from) inWhitelist(to) returns (bool) {
        if (allowance[from][msg.sender] != uint256(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }

        _transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function mint(address to, uint256 amount) external {
        require(minter[msg.sender], "WrappedToken: Caller is not Minter");
        _mint(to, amount);
    }

    function burn(address user, uint256 amount) external {
        require(minter[msg.sender], "WrappedToken: Caller is not Minter");
        _burn(user, amount);
    }

    function _mint(address user, uint256 amount) internal {
        balanceOf[user] = balanceOf[user].add(amount);
        emit Transfer(address(0), user, amount);
    }

    function _burn(address user, uint256 amount) internal {
        require(balanceOf[user] >= amount, "WrappedToken: Amount too large");
        balanceOf[user] = balanceOf[user].sub(amount);
        emit Transfer(user, address(0), amount);
    }

    function setMinter(address newMinter, bool flag) external onlyOwner {
        minter[newMinter] = flag;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 decimals_
    ) external onlyOwner {
        _name = name_;
        _symbol = symbol_;
        _decimals = uint8(decimals_);
    }
}
