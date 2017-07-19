using Gtk.ShortNames, Graphics
function fillLEDs(ctx, h, w, ledData)
    rect_size = floor(Int, w/size(ledData,2))
    #@show size(ledData)
    for i in 1:size(ledData, 3)
        for j in 1:size(ledData, 2)
            rectangle(ctx, (j-1)*(rect_size), (i-1)*(rect_size+10), rect_size, rect_size)
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
    set_source_rgb(ctx,1,1,1)
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
function main()
    const NUM_LEDS = 600
    const NUM_ROWS = 4
    const LED_PER_ROW = floor(Int, NUM_LEDS/NUM_ROWS)
    const BYTES_PER_LED = 3
    const PORT = 8080
    exited = false
    udpSock = UDPSocket()
    bind(udpSock,ip"127.0.0.1",PORT)
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
main()
