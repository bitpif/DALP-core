pragma solidity ^0.6.6;

import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {FixedPoint} from "@uniswap/lib/contracts/libraries/FixedPoint.sol";
import {UniswapV2OracleLibrary} from "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import {UniswapV2Library} from "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
// import {UniswapV2Library} from "@uniswap/lib/contracts/libraries/UniswapV2Library.sol";

contract OracleManager {
    using FixedPoint for *;

    uint public constant PERIOD = 1 hours;

    address private factory;
    address private weth;

    struct OraclePairState {
        IUniswapV2Pair pair;
        address token0;
        address token1;
        uint price0CumulativeLast;
        uint price1CumulativeLast;
        uint32 blockTimestampLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    mapping(address => OraclePairState) oraclePairs;

    // mapping where you can insert both assets in either order
    // to pull correct oracleState struct
    // mapping[a][b] = struct
    // mapping[b][a] = struct
    // OR...
    // sort in discrete way using some measurement => deterministic output

    // addPair function instead of constructor instantiation
    // addPair is called on the first time liquidity is migrated to a pair

    // update and consult methods need have specified parameters to update/consult correct pair

    // when user mints, manager contract needs to know which token pair is active

    constructor(address _factory, address _weth) public {
        factory = _factory;
        weth = _weth;
    }

    // add oracle pair: weth<=>token
    function addPair(address token) public {
        require(oraclePairs[token].blockTimestampLast == 0, "Pair already exists");
        IUniswapV2Pair pair = getUniswapPair(token);
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, 'Oracle Manager: NO_RESERVES');

        OraclePairState storage oraclePair;
        oraclePair.pair = pair;
        oraclePair.token0 = pair.token0();
        oraclePair.token1 = pair.token1();
        oraclePair.price0CumulativeLast = pair.price0CumulativeLast();
        oraclePair.price1CumulativeLast = pair.price1CumulativeLast();
        oraclePair.blockTimestampLast = blockTimestampLast;

        oraclePairs[token] = oraclePair;
    }

    modifier oraclePairExists(address token) {
        require(oraclePairs[token].token1 == token, "Oracle token pair must exist");
        _;
    }


    function update(address token) external oraclePairExists(token) {
        IUniswapV2Pair pair = getUniswapPair(token);
        (uint32 blockTimestamp, uint price0Cumulative, uint price1Cumulative) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));

        OraclePairState storage oraclePair = oraclePairs[token];    
        uint32 timeElapsed = blockTimestamp - oraclePair.blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        // require(timeElapsed >= PERIOD, 'ExampleOracleSimple: PERIOD_NOT_ELAPSED');
        if(timeElapsed >= PERIOD) return;

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        oraclePair.price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - oraclePair.price0CumulativeLast) / timeElapsed));
        oraclePair.price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - oraclePair.price1CumulativeLast) / timeElapsed));

        oraclePair.price0CumulativeLast = price0Cumulative;
        oraclePair.price1CumulativeLast = price1Cumulative;
        oraclePair.blockTimestampLast = blockTimestamp;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    // address token must be non-weth token
    function consult(address token, uint amountIn) external view oraclePairExists(token) returns (uint amountOut) {
        require(token != weth, "Must be non-WETH token in pair");
        // require(oraclePairs[token], "Oracle token pair must exist");

        IUniswapV2Pair pair = getUniswapPair(token);
        OraclePairState memory oraclePair = oraclePairs[token];

        amountOut = oraclePair.price1Average.mul(amountIn).decode144();
    }

    function getUniswapPair(address token) public view returns(IUniswapV2Pair pair){
        pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, weth, token));
    }
}
