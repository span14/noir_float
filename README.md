# Floating Arithmetics in Noir

## Description
This project reproduces floating arithmetics in Noir using algorithms in [Zero-Knowledge Location Privacy via Accurate Floating Point SNARKs](https://arxiv.org/abs/2404.14983). The precision error is low and the constraints are considerable in production level usage. 

## Usage
```
# Import the floating point library

let a = FP32::new(0x1111/4369);
let b = FP32::new(0x8888/34952);

# Addition
let c = a.add(b);

# Multiplication
let d = a.mul(b);

```

## Reference
- [Zero-Knowledge Location Privacy via Accurate Floating Point SNARKs](https://arxiv.org/abs/2404.14983)