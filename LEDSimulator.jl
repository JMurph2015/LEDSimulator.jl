__precompile__(true)
module LEDSimulator
export main

using Gtk.ShortNames, Graphics, JSON

function fillLEDs(ctx, h, w, ledData)
    rect_width = floor(Int, w/size(ledData,2))
    rect_height = floor(Int, h/size(ledData,3))
    #@show size(ledData)
    for i in 1:size(ledData, 3)
        for j in 1:size(ledData, 2)
            rectangle(ctx, (j-1)*(rect_width), (i-1)*(rect_height), rect_width, rect_height)
            set_source_rgb(ctx, (ledData[:,j,i]/255)...)
            fill(ctx)
        end
    end
end
function clear(c::Canvas)
    ctx = getgc(c)
    h = height(c)
    w = width(c)
    rectangle(ctx, 0,0,w,h)
    set_source_rgb(ctx,0,0,0)
    fill(ctx)
end
function redraw(c, ledData)
    @guarded draw(c) do widget
        ctx = getgc(c)
        h = height(c)
        w = width(c)
        clear(c)
        fillLEDs(ctx, h, w, ledData)
    end
end

function setup_server_connection(name, led_per_row, num_rows, main_udpsock, main_port, setup_port)
    #macString = readstring(`cat /sys/class/net/eth0/address`)
    ipString = split(readstring(`hostname -I`))[1]
    out_dict = Dict(
        "name"=>name,
        "ip"=>ipString,
        "port"=>main_port,
        "mac"=>"mac address here",
        "numStrips"=>num_rows,
        "numAddrs"=>led_per_row*num_rows,
        "strips"=>[
            Dict(
                "name"=>"test$i",
                "startAddr"=>1+(i-1)*led_per_row,
                "endAddr"=>i*led_per_row,
                "channel"=>i
            )
            for i in 1:num_rows
        ]
    )
    timeout_length = 60
    timeout = false
    @async begin
        sleep(timeout_length)
        timeout=true
    end
    while !timeout
        tmp = recvfrom(main_udpsock)
        json_data = Dict{String,String}()
        try
            json_data = JSON.parse(convert(String, tmp[2]))
        catch
            print("json error")
        end
        if validate_json(json_data)
            send(main_udpsock, tmp[1], setup_port, json(out_dict))
            break
        end
    end
end

function main(n, ledprow, numrow, port, setup)
    const name = n
    const LED_PER_ROW = ledprow
    const NUM_ROWS = numrow
    const NUM_LEDS = LED_PER_ROW*NUM_ROWS
    const BYTES_PER_LED = 3
    const PORT = port
    const SETUP_PORT = setup

    udpSock = UDPSocket()
    bind(udpSock,ip"127.0.0.1",PORT)

    setup_server_connection(name, LED_PER_ROW, NUM_ROWS, udpSock, PORT, SETUP_PORT)
    
    exited = false
    NUM_LEDS % NUM_ROWS == 0 || error("Number of leds must be evenly divisible by number of rows")
    ledData = zeros(UInt8, 3, NUM_ROWS, LED_PER_ROW)
    c = @Canvas()
    win = Window(c, "My Window", 600, 400, true, true)
    @async begin
        show(c)
        while !exited
            recvData = recv(udpSock)
            if typeof(recvData) == Vector{UInt8}
                #print(size(recvData))
                ledData = reshape(recvData[1:BYTES_PER_LED*NUM_LEDS], BYTES_PER_LED, LED_PER_ROW, NUM_ROWS)
                #println(typeof(ledData))
                redraw(c, ledData)
            end
        end
    end
    if !isinteractive()
        cx = Condition()
        signal_connect(win, :destroy) do widget
            notify(cx)
            exited = true
        end
        wait(cx)
    end
end

function validate_json(json_data::Dict{String,Any})
    ref_dict = Dict(
        "ip"=>"",
        "mac"=>"",
        "msg_type"=>""
    )
    return collect(keys(json_data)) == collect(keys(ref_dict))
end

check_json(x::T, y::T) where {T<:Dict{String, N} where N<:Any} = check_symmetry(x,y)
check_json(x::T, y::N) where {T,N} = false

function check_symmetry(x::T, y::T) where {T<:Dict{S, N} where {S<:Any, N<:Any}}
    if collect(keys(x)) == collect(keys(y))
        return reduce(check_symmetry.(collect(values(x)), collect(values(y)))) do x, y
            return x && y
        end
    else
        return false
    end
end

function check_symmetry(x::AbstractArray, y::AbstractArray)
    try
        return reduce(check_symmetry.(x,y)) do x, y
            return x && y
        end
    catch
        return false
    end
end

check_symmetry(x::T, y::T) where T<:Union{Number, String, Bool} = true
check_symmetry(x::T, y::N) where {T, N} = false

end