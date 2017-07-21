push!(LOAD_PATH,pwd())
using LEDSimulator
const n = "1"
const ledprow = 350
const numrow = 60
const port = 8080
const setup = 37322
main(n, ledprow, numrow, port, setup)