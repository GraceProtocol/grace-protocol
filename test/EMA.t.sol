// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "../src/EMA.sol";

contract EMATest is Test {

    // use EMA
    using EMA for EMA.EMAState;

    function test_init() public {
        EMA.EMAState memory emaState;
        uint halfLife = 100;
        emaState = emaState.init(halfLife);
        assertEq(emaState.ema, 0);
        assertEq(emaState.halfLife, halfLife * 1e18 / 693147180559945300);
        assertEq(emaState.lastUpdate, block.timestamp);
    }

    function test_update() public {
        EMA.EMAState memory emaState;
        uint halfLife = 7 days;
        emaState = emaState.init(halfLife);
        assertEq(emaState.ema, 0);
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.5 * 1e18, uint(1e12));
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.75 * 1e18, uint(1e12));
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.875 * 1e18, uint(1e12));
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.9375 * 1e18, uint(1e12));
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.96875 * 1e18, uint(1e12));
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.984375 * 1e18, uint(1e12));
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.9921875 * 1e18, uint(1e12));
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.99609375 * 1e18, uint(1e12));
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.998046875 * 1e18, uint(1e12));
        skip(7 days);
        emaState = emaState.update(1 * 1e18);
        assertApproxEqAbs(emaState.ema, 0.9990234375 * 1e18, uint(1e12));
        
        skip(100); // 100 seconds manipulation
        emaState = emaState.update(1000 * 1e18); // artificially inflated by 1000
        assertApproxEqAbs(emaState.ema, 1 * 1e18, uint(1e18));
        
    }

    function test_wadExp() public {
        assertEq(EMA.wadExp(0), 1e18);
        assertEq(EMA.wadExp(1e18), 2718281828459045235);
        assertEq(EMA.wadExp(-1e18), 367879441171442321);
        assertEq(EMA.wadExp(2e18), 7389056098930650227);
        assertEq(EMA.wadExp(-2e18), 135335283236612691);
    }

    function test_setHalfLife() public {
        EMA.EMAState memory emaState;
        uint halfLife = 7 days;
        emaState = emaState.init(halfLife);
        emaState = emaState.setHalfLife(halfLife * 2);
        assertEq(emaState.halfLife, (halfLife*2) * 1e18 / 693147180559945300);
    }

}