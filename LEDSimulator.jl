__precompile__(true)
module LEDSimulator
export main

using JSON, ModernGL, GLAbstraction, GeometryTypes
import GLFW 

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

    window = GLFW.CreateWindow(640,480, "LEDSimulator.jl")
    GLFW.MakeContextCurrent(window)

    vao = Ref(GLuint(0))
    glGenVertexArrays(1, vao)
    glBindVertexArray(vao[])

    const vert_shader = vert"""
        {{GLSL_VERSION}}
        in vec2 position;
        in vec3 color;

        out vec3 Color;

        void main()
        {
            Color = color;
            gl_Position = vec4(position, 0.0, 1.0);
        }
    """
    const frag_shader = frag"""
        {{GLSL_VERSION}}
        in vec3 Color;
        out vec4 color;

        void main()
        {    
            color = vec4(Color, 1.0);
        }
    """
    vertex_positions, elements = getVertices(LED_PER_ROW, NUM_ROWS)

    vertex_colors = getVertexColors(NUM_LEDS)
    bufferdict = Dict(
        :position=>GLBuffer(vertex_positions),
        :color=>GLBuffer(vertex_colors),
        :indexes=>indexbuffer(elements)
    )
    ro = std_renderobject(bufferdict, LazyShader(vert_shader, frag_shader))
    exited = false
    NUM_LEDS % NUM_ROWS == 0 || error("Number of leds must be evenly divisible by number of rows")
    recvData = zeros(UInt8, BYTES_PER_LED*NUM_LEDS)
    glClearColor(0,0,0,0)
    @async begin
        while !exited
            recvData = recv(udpSock)
            if typeof(recvData) == Vector{UInt8} && length(recvData) == BYTES_PER_LED*NUM_LEDS
                update!(bufferdict, recvData[1:3*NUM_LEDS], LED_PER_ROW, NUM_ROWS)
            end
        end
    end
    while !GLFW.WindowShouldClose(window)
        glClear(GL_COLOR_BUFFER_BIT)
        GLAbstraction.render(ro)
        GLFW.SwapBuffers(window)
        GLFW.PollEvents()
        if GLFW.GetKey(window, GLFW.KEY_ESCAPE) == GLFW.PRESS
            GLFW.SetWindowShouldClose(window, true)
        end
        yield()
    end
    exited = true
    GLFW.DestroyWindow(window)
end

function getVertices(leds_per_row, num_rows)
    slotwidth = convert(Float32, 2/leds_per_row)
    slotheight = convert(Float32, 2/num_rows)
    # Adjust the computation for one indexing.  Good ole one-indexing.
    rect_template = [
        Float32[ 0.0f0,             0.95f0*slotheight],
        Float32[ 0.95f0*slotwidth,  0.95f0*slotheight],
        Float32[ 0.95f0*slotwidth,  0.0f0],
        Float32[ 0.0f0,             0.0f0],
    ]
    get_slot(x,y) = Float32[((x-1)*slotwidth)-1, ((y-1)*slotheight)-1]

    stuff = [rect_template[i].+get_slot(j,k) for i in 1:4, j in 1:leds_per_row, k in 1:num_rows]
    out = [Point{2,Float32}(stuff[i]...) for i in eachindex(stuff)]
    elems = vcat(reshape([[(i-1,i,i+1), (i+1,i+2,i-1)] for i in 1:4:length(out)], :, 1)...)
    elements = [Face{3, UInt32}(elems[i]...) for i in 1:length(elems)]
    return out, elements
end

function getVertexColors(numLED)
    return Vec3f0[(0.0f0,0.4f0,1.0f0) for i in 1:4*numLED]
end

function update!(bufferdict, ledData, ledperrow, numrow)
    len::Int = length(ledData)
    for i in eachindex(bufferdict[:color])
        tmp::Int = floor(Int, (i-1)/4)
        row::Int = floor(Int, tmp/ledperrow)+1
        idx::Int = len + 3*((tmp - (row-1)*ledperrow) - row*ledperrow) + 1
        bufferdict[:color][i] = Vec{3,Float32}(ledData[idx:idx+2])/255.0f0
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