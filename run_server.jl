push!(LOAD_PATH,pwd())
using LEDSimulator
const n = "1"
const ledprow = 300
const numrow = 30
const port = 8080
const setup = 37322
main(n, ledprow, numrow, port, setup)