use crate::arithmetic::Arithmetic;
use crate::utils::range_check_lookup;
use dep::std::println;

struct FP32 {
    s: Field,
    e: Field,
    m: Field,
    a: Field,
}

unconstrained fn msb(v: Field, l: u64) -> Field {
    ((v as u64 >> (l-1)) & 1) as Field
}

unconstrained fn normalize(m: Field, l: u64) -> u32 {
    let mut m_t = m as u64;
    let mut shift: u32 = 0;
    let msb = 1 << l;
    if (m_t == 0) {
        shift
    } else {
        for _ in 0..l {
            if (m_t & msb) != 0 {
                break;
            }
            shift += 1;
            m_t <<= 1;
        }
        shift
    }
}

unconstrained fn decompose(v: u32) -> (Field, Field, Field) {
    let s = v >> 31;
    let e = (v >> 23) & 0xff;
    let m = v & 0x7fffff;
    (s as Field, e as Field, m as Field)
}

unconstrained fn split(v: Field, N: Field) -> (Field, Field, Field, Field) {
    let s = U128::from_integer(v);
    let N = U128::from_integer(N);
    let one = U128::from_integer(1);
    let l = U128::from_integer(24);
    let u = (s >> (N-l+one)) & ((one << (l-one))-one);
    let b1 = (s >> (N-l)) & one;
    let v = s & (( one << (N-l-one)) -one);
    let b2 = (s >> (N-l-one)) & one;
    (u.to_integer(), b1.to_integer(), v.to_integer(), b2.to_integer())
}

unconstrained fn shift_left(v: Field, l: Field) -> Field {
    let v = U128::from_integer(v);
    let l = U128::from_integer(l);
    let res = v << l;
    res.to_integer()
}

unconstrained fn exp(v: Field) -> Field {
    2.pow_32(v)
}

unconstrained fn gez(v: Field) -> Field {
    v.lt(1/2) as Field
}

impl FP32 {
    fn new(v: u32) -> FP32 {
        let (s, e, m) = decompose(v);
        assert(s * (1 - s) == 0);
        range_check_lookup(e, 8);
        range_check_lookup(m, 23);
        let m_is_0 = (m == 0) as Field;
        let e_is_min = (e == 0) as Field;
        let e_is_max = (e == 255) as Field;
        let d = normalize(m, 22);
        let shifted_m = m * FP32::exp(d as Field);
        // TODO: this sounds questionable
        range_check_lookup(
            shifted_m - (1-m_is_0) * exp(22), 23
        );
        let e = 1 - exp(7) + ( e_is_min * (( m_is_0 * ( -23 + d as Field - 1) + 1 - d as Field) - e) + e);

        let m = (1-(e_is_max * (1 - m_is_0))) * (e_is_min * (shifted_m - m - exp(23)) + m + exp(23));

        FP32 {
            s, e, m,
            a: e_is_max as Field
        }
    }

    fn round(e: Field, m: Field, N: Field, delta: Field, K: Field, flag: Field) -> (Field, Field) {
        
        let (u, b1, v, b2) = split(shift_left(m, K-delta), N+K);

        range_check_lookup(u, 23);
        assert(b1 * (1 - b1) == 0);
        range_check_lookup(v, (N-25+K) as u32);
        assert(b2 * (1 - b2) == 0);
        let delta_shift = FP32::exp(delta);
        let comm = N + K - 25;
        let u = u * 2 + b1;
        let v = b2 * exp(comm) + v;
        assert(
            m * exp(K) ==
            u * exp(comm+1+delta) + v * delta_shift
        );
        let half = ( v == exp(N-25+K)) as Field * flag;
        let m = (u + half * (b1-b2) + b1) * delta_shift;
        let overflow = (u == exp(24)) as Field;
        let e  = e + overflow;
        let m = overflow * (exp(24) - m) + m;
        (e, m)
    }

    fn nzero() -> Self {
        FP32 {
            s: 1,
            e: 1-23-exp(7),
            m: 0,
            a: 0
        }
    }

    fn pzero() -> Self {
        FP32 {
            s: 0,
            e: 1-23-exp(7),
            m: 0,
            a: 0,
        }
    }

    fn ninfinity() -> Self {
        FP32 {
            s: 1,
            e: 255,
            m: exp(23),
            a: 0
        }
    }

    fn pinfinity() -> Self {
        FP32 {
            s: 0,
            e: 255,
            m: exp(23),
            a: 0
        }
    }

    fn abs(v: Field, l: u32) -> (Field, Field) {
        let s = gez(v);
        assert(s * (1 - s) == 0);
        let abs = s * (2 * v ) - v;
        range_check_lookup(abs, l);
        (s, abs)
    }

    fn max(x: Field, y: Field, l: u32) -> Field {
        let (s, abs) = FP32::abs(x - y, l);
        let max = y + s * abs;
        max
    }

    fn min(x: Field, y: Field, l: u32) -> Field {
        let (s, abs) = FP32::abs(x - y, l);
        let min = x - s * abs;
        min
    }

    fn exp(e: Field) -> Field {
        2.pow_32(e)
    }

}

impl Arithmetic for FP32 {
    fn add(self, other: Self) -> Self {
        // Align exponents and add signed mantissas
        let (c, abs) = FP32::abs(other.e - self.e, 9);
        let e = c * (other.e - self.e) + self.e;
        let abs = FP32::min(abs, 26, 8);
        let sa = (1 - 2 * self.s) * self.m;
        let sb = (1 - 2 * other.s) * other.m;
        let sa_sb = (sa == sb) as Field;
        let x = (c * (sb - sa) + sa) * exp(26);
        let y = (c * (sa - sb) + sb) * FP32::exp(26-abs);
        let z = x + y;
        let (s, m) = FP32::abs(z, 51);
        let s = 1 - s;
        let e = e + 1;
        let a = self.a * (1- other.a) + other.a;
        // Normalize intermediate mantissa
        let m_is_0 = (m == 0) as Field;
        let d = normalize(m, 50) as Field;
        let m = m * FP32::exp(d);
        let e = e-d;
        range_check_lookup(
            m - (1-m_is_0) * exp(50),
            50
        );
        // Rounding intermediate mantissa
        let (e, m) = FP32::round(e, m, 51, 0, 0, 1);
        let (t, _) = FP32::abs(e - exp(7), 9);
        let a = a * t;
        let s = (self.s == other.s) as Field * (self.s - s) + s;
        let e = (1-a) * ((m_is_0 * (1-exp(7)-23 - e) + e) - exp(7)) + exp(7);
        let m1 = ((1-other.a) * (1 - sa_sb) + sa_sb) * self.m;
        let m2 = (1-self.a) * ((a * (exp(23) - m) + m) - other.m) + other.m;
        let m = self.a * (m1 - m2) + m2;
        
        FP32 {
            s, e, m, a
        }
    }

    fn mul(self, other: Self) -> Self {
       let s = self.s * (1 - 2*other.s) + other.s; 
       let e = self.e + other.e;
       let m = self.m * other.m;
       let a = self.a * (1-other.a) + other.a;
       let b = msb(m, 48);
       assert(b * (1 - b) == 0);
       range_check_lookup(m - b * exp(47), 48);
       let m = 2*m - b * m;
       let e = e + b;
       let delta = FP32::max(
            FP32::min(
                -126 - e,
                25,
                9
            ),
            0,
            9
        );
        let (e, m) = FP32::round(e, m, 48, delta, 25, 1);
        let (t, _) = FP32::abs(e - 128, 9);
        let a = a * (1-t) + t;
        let m_is_0 = (m == 0) as Field;
        let e = (1 - a) * ((m_is_0 * (-150 - e) + e) - 128) + 128;
        let m = (a * (1-m_is_0)) * (exp(23) - m) + m;
        FP32 {
            s, e, m, a
        }
    }

}

#[test]
fn test_norm_fp32() {
    let a = FP32::new(0x40e40000);

    assert(a.s == 0);
    assert(a.e == 2);
    assert(a.m == 14942208);
}

#[test]
fn test_add_fp32() {
    let a = FP32::new(1097785672);
    let b = FP32::new(1100155453);
    let c = a.add(b);
    let c_p = FP32::new(1107639665);
    println(c);
    println(c_p);
}

#[test]
fn test_mul_fp32_1() {
    let a = FP32::new(1097785672);
    let b = FP32::new(1100155453);
    let c = a.mul(b);
    let c_p = FP32::new(1133065450);
    assert(c.s == c_p.s);
    assert(c.e == c_p.e);
    assert(c.m == c_p.m);
}

#[test]
fn test_mul_fp32_2() {
    let a = FP32::new(1120237519);
    let b = FP32::new(3248098378);
    let c = a.mul(b);
    let c_p = FP32::new(3303909146);
    assert(c.s == c_p.s);
    assert(c.e == c_p.e);
    assert(c.m == c_p.m);
}