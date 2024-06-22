mod utils;
mod arithmetic;
mod float32;
mod float64;


fn main(x: u32, y: pub u32) {
    let x = float32::FP32::new(x);
    let y = float32::FP32::new(y);
    x.add(y);
}

