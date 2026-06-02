import os
import tensorflow as tf
from tensorflow.keras import layers, models
from tensorflow.keras.preprocessing.image import ImageDataGenerator
from tensorflow.keras.utils import load_img, img_to_array
import numpy as np
import json


gpus = tf.config.list_physical_devices('GPU')
if gpus:
    try:
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
        print(" GPU memory growth enabled")
    except RuntimeError as e:
        print(e)


img_width, img_height = 128, 128
batch_size = 16
epochs = 30

train_data_dir = r"D:\Projects\Green-Guard-AI\DATA-SET\Train"
validation_data_dir = r"D:\Projects\Green-Guard-AI\DATA-SET\Validation"
test_data_dir = r"D:\Projects\Green-Guard-AI\DATA-SET\Train"


class_mapping = {
    0: ('Generic', 'Healthy'),
    1: ('Generic', 'Powdery'),
    2: ('Generic', 'Rusty'),
    3: ('CORN', 'Rust'),
    4: ('CORN', 'Gray Spot'),
    5: ('CORN', 'Healthy'),
    6: ('CORN', 'Leaf Blight'),
    7: ('Potato', 'Early Blight'),
    8: ('Potato', 'Healthy'),
    9: ('Potato', 'Late Blight'),
    10: ('SugarCane', 'Bacteria Blight'),
    11: ('SugarCane', 'Healthy'),
    12: ('SugarCane', 'RedRot'),
    13: ('Wheat', 'Brown Rust'),
    14: ('Wheat', 'Healthy'),
    15: ('Wheat', 'Yellow Rust'),
   
}
num_classes = len(class_mapping)


with open("class_mapping.json", "w") as f:
    json.dump(class_mapping, f)
print(" Class mapping saved as class_mapping.json")


train_datagen = ImageDataGenerator(
    rescale=1./255,
    shear_range=0.2,
    zoom_range=0.2,
    rotation_range=20,
    width_shift_range=0.2,
    height_shift_range=0.2,
    horizontal_flip=True,
    vertical_flip=True
)

val_datagen = ImageDataGenerator(rescale=1./255)
test_datagen = ImageDataGenerator(rescale=1./255)

train_generator = train_datagen.flow_from_directory(
    train_data_dir,
    target_size=(img_width, img_height),
    batch_size=batch_size,
    class_mode='categorical',
    shuffle=True
)

validation_generator = val_datagen.flow_from_directory(
    validation_data_dir,
    target_size=(img_width, img_height),
    batch_size=batch_size,
    class_mode='categorical',
    shuffle=False
)

test_generator = test_datagen.flow_from_directory(
    test_data_dir,
    target_size=(img_width, img_height),
    batch_size=batch_size,
    class_mode='categorical',
    shuffle=False
)


model = models.Sequential([
    layers.Conv2D(16, (3, 3), activation='relu', input_shape=(img_width, img_height, 3)),
    layers.MaxPooling2D((2, 2)),

    layers.Conv2D(32, (3, 3), activation='relu'),
    layers.MaxPooling2D((2, 2)),

    layers.Conv2D(64, (3, 3), activation='relu'),
    layers.MaxPooling2D((2, 2)),

    layers.Flatten(),
    layers.Dense(128, activation='relu'),
    layers.Dropout(0.5),
    layers.Dense(num_classes, activation='softmax')
])

model.compile(
    optimizer=tf.keras.optimizers.Adam(learning_rate=1e-4),
    loss='categorical_crossentropy',
    metrics=['accuracy']
)

model.summary()


print("\n Starting training...\n")
history = model.fit(
    train_generator,
    steps_per_epoch=max(1, train_generator.samples // batch_size),
    epochs=epochs,
    validation_data=validation_generator,
    validation_steps=max(1, validation_generator.samples // batch_size)
)


print("\n Evaluating model...\n")
test_loss, test_acc = model.evaluate(test_generator, steps=max(1, test_generator.samples // batch_size))
print(f"Test Accuracy: {test_acc:.3f}")


model.save('plant_disease_model.h5')
print("Keras model saved as plant_disease_model.h5")


print("\n Converting to TensorFlow Lite...\n")
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_model = converter.convert()

with open('plant_disease_model.tflite', 'wb') as f:
    f.write(tflite_model)

print("TFLite model saved successfully: plant_disease_model.tflite")

print("\n Testing on a single image...\n")


img_path = r"D:\Shivam\Tree AI\Tree AI\SampleTest\leaf.jpg"


img = load_img(img_path, target_size=(img_width, img_height))
img_array = img_to_array(img) / 255.0
img_array = np.expand_dims(img_array, axis=0)


prediction = model.predict(img_array)
predicted_class = tf.argmax(prediction[0]).numpy()
species, disease = class_mapping[predicted_class]

print(f"\n Predicted Species: {species}")
print(f" Predicted Disease: {disease}")
