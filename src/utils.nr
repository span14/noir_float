use dep::std;

pub fn range_check_lookup(v: Field, l: u32) {
    v.assert_max_bit_size(l);
}


