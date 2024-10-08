// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IERC20 {
    function decimals() external view returns (uint256);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address _spender, uint256 _value) external;

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface ISwapRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );
}

interface ISwapFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

abstract contract Ownable {
    address internal _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "!owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "new is 0");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract PreSale is Ownable {
    string public name;

    address public tokenAddr;
    address payable public fundAddress;

    uint256 private constant MAX = ~uint256(0);

    address public _mainPair;
    IERC20 public _mintToken;
    ISwapRouter public _swapRouter;
    ISwapFactory public _swapFactory;

    bool public start;
    bool public enableAddLP;

    uint256 public addPart;
    uint256 public price;
    uint256 public minted;
    uint256 public amountPerUnits;
    uint256 public mintLimit;

    event PreSaleCreated(string name, address tokenAddr);

    constructor(
        string[] memory stringParams,
        address[] memory addressParams,
        uint256[] memory numberParams,
        bool[] memory boolParams
    ) {
        name = stringParams[0];
        tokenAddr = address(addressParams[0]);

        _mintToken = IERC20(tokenAddr);

        _owner = tx.origin;

        price = numberParams[0];

        amountPerUnits = numberParams[1];

        mintLimit = numberParams[2];

        enableAddLP = boolParams[0];

        addPart = numberParams[3];

        _swapRouter = ISwapRouter(address(addressParams[1]));

        _mintToken.approve(address(_swapRouter), MAX);

        fundAddress = payable(_owner);

        emit PreSaleCreated(name,tokenAddr);
    }

    function isContract(address _addr) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function setClaims(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).transfer(msg.sender, amount);
        }
    }

    event AddEvent(
        address indexed to,
        uint256 amount,
        uint256 ethAmount,
        uint256 liquidity
    );

    function launch() external onlyOwner {
        require(!start, "started");
        _mintToken.transferFrom(
            msg.sender,
            address(this),
            amountPerUnits * mintLimit
        );
        start = true;
    }

    function setMintLimit(uint256 newValue) public onlyOwner {
        mintLimit = newValue;
    }

    function setPrice(uint256 newValue) public onlyOwner {
        price = newValue;
    }

    function setAmountPerUnits(uint256 newValue) public onlyOwner {
        amountPerUnits = newValue;
    }

    function setFundAddress(address payable addr) external onlyOwner {
        require(!isContract(addr), "fundaddress is a contract ");
        fundAddress = addr;
    }

    event Minted(address indexed to, uint256 amount, uint256 ethAmount);

    event Refund(address indexed from, uint256 bnb);

    receive() external payable {
        if (start) {
            mint();
        }
    }

    function mint() internal {
        require(msg.value >= price, "value not match");
        require(!isContract(msg.sender), "can not mint to contract");
        require(msg.sender == tx.origin, "can not mint to contract.");

        uint256 units = msg.value / price;
        uint256 realCost = units * price;
        uint256 refund = msg.value - realCost;

        require(minted + units <= mintLimit, "exceed max mint");
        require(
            units * amountPerUnits <= _mintToken.balanceOf(address(this)),
            "not enough balance"
        );
        if (enableAddLP) {
            uint256 addETHAmount = (realCost * addPart) / 100;
            uint256 addTokenAmount = (units * amountPerUnits * addPart) / 100;
            AddLiquidity(addETHAmount, addTokenAmount, msg.sender);
            if (realCost - addETHAmount > 0) {
                fundAddress.transfer(realCost - addETHAmount);
            }
        } else {
            bool success = _mintToken.transfer(
                msg.sender,
                units * amountPerUnits
            );
            if (success) {
                minted += units;
                emit Minted(msg.sender, units * amountPerUnits, realCost);
            }
        }

        if (refund > 0) {
            payable(msg.sender).transfer(refund);
            emit Refund(msg.sender, refund);
        }
    }

    function AddLiquidity(
        uint256 ETHAmount,
        uint256 tokenAmount,
        address lpToAddr
    ) internal {
        _swapFactory = ISwapFactory(_swapRouter.factory());

        address _weth = _swapRouter.WETH();
        address _pair = _swapFactory.getPair(tokenAddr, _weth);

        if (_pair == address(0)) {
            _mainPair = _swapFactory.createPair(tokenAddr, _weth);
        }
        // add liquidity
        (
            uint256 addTokenAmount,
            uint256 ethAmount,
            uint256 liquidity
        ) = _swapRouter.addLiquidityETH{value: ETHAmount}(
                tokenAddr, // token
                tokenAmount, // token desired
                0, // token min
                0, // eth min
                lpToAddr, // lp to
                block.timestamp + 60 // deadline
            );

        emit AddEvent(lpToAddr, addTokenAmount, ethAmount, liquidity);
    }
}