using MNIST, ReverseDiff

const BATCH_SIZE = 100
const IMAGE_SIZE = 784
const CLASS_COUNT = 10

##################
# data wrangling #
##################

# loading MNIST data #
#--------------------#

function load_mnist(data)
    images, label_indices = data
    labels = zeros(CLASS_COUNT, length(label_indices))
    for i in eachindex(label_indices)
        labels[Int(label_indices[i]) + 1, i] = 1.0
    end
    return images, labels
end

const TRAIN_IMAGES, TRAIN_LABELS = load_mnist(MNIST.traindata())
const TEST_IMAGES, TEST_LABELS = load_mnist(MNIST.testdata())

# loading batches #
#-----------------#

immutable Batch{W,B,P,L}
    weights::W
    bias::B
    pixels::P
    labels::L
end

function Batch(images, labels, i)
    weights = zeros(CLASS_COUNT, IMAGE_SIZE)
    bias = zeros(CLASS_COUNT)
    range = i:(i + BATCH_SIZE - 1)
    return Batch(weights, bias, images[:, range], labels[:, range])
end

function load_batch!(batch, images, labels, i)
    offset = i - 1
    for batch_col in 1:BATCH_SIZE
        data_col = batch_col + offset
        for k in 1:size(images, 1)
            batch.pixels[k, batch_col] = images[k, data_col]
        end
        for k in 1:size(labels, 1)
            batch.labels[k, batch_col] = labels[k, data_col]
        end
    end
    return batch
end

####################
# model definition #
####################

# objective definitions #
#-----------------------#

function softmax(x)
    exp_x = exp.(x)
    denom = sum(exp_x)
    return exp_x ./ denom
end

ReverseDiff.@forward negative_log(x::Real) = -log(x)

cross_entropy(y′, y) = mean(sum(y′ .* (negative_log.(y)), 1))

function model(weights, bias, pixels, labels)
    y = softmax((weights * pixels) .+ bias)
    return cross_entropy(labels, y)
end

# gradient definitions #
#----------------------#

# generate `∇model!(output, input)` where the output/input takes the same form as `seeds`
const ∇model! = begin
    batch = Batch(TRAIN_IMAGES, TRAIN_LABELS, 1)
    seeds = (batch.weights, batch.bias, batch.pixels, batch.labels)
    ReverseDiff.compile_gradient(model, seeds)
end

# add convenience method to `∇model!` that translates `Batch` args to `Tuple` args
function (::typeof(∇model!))(output::Batch, input::Batch)
    output_tuple = (output.weights, output.bias, output.pixels, output.labels)
    input_tuple = (input.weights, input.bias, input.pixels, input.labels)
    return ∇model!(output_tuple, input_tuple)
end

############
# training #
############

function train_step!(∇batch::Batch, batch::Batch, rate = 0.5, iters = 20)
    for _ in 1:iters
        ∇model!(∇batch, batch)
        for i in eachindex(batch.weights)
            batch.weights[i] -= rate * ∇batch.weights[i]
        end
        for i in eachindex(batch.bias)
            batch.bias[i] -= rate * ∇batch.bias[i]
        end
    end
end

function train!(∇batch::Batch, batch::Batch, images, labels, rate = 0.5, iters = 20)
    batch_count = floor(Int, size(images, 2) / BATCH_SIZE)
    for i in 1:batch_count
        load_batch!(batch, images, labels, i)
        train_step!(∇batch, batch, rate, iters)
    end
    return ∇batch
end