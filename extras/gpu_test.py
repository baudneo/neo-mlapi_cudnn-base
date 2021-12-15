#!/usr/bin/python3
import numpy as np
import argparse
import cv2
import os
import time


def extract_boxes_confidences_classids(outputs, confidence, width, height):
    boxes = []
    confidences = []
    classIDs = []

    for output in outputs:
        for detection in output:
            # Extract the scores, classid, and the confidence of the prediction
            scores = detection[5:]
            classID = np.argmax(scores)
            conf = scores[classID]

            # Consider only the predictions that are above the confidence threshold
            if conf > confidence:
                # Scale the bounding box back to the size of the image
                box = detection[0:4] * np.array([width, height, width, height])
                centerX, centerY, w, h = box.astype('int')

                # Use the center coordinates, width and height to get the coordinates of the top left corner
                x = int(centerX - (w / 2))
                y = int(centerY - (h / 2))

                boxes.append([x, y, int(w), int(h)])
                confidences.append(float(conf))
                classIDs.append(classID)

    return boxes, confidences, classIDs


def draw_bounding_boxes(image, boxes, confidences, classIDs, idxs, colors):
    if len(idxs) > 0:
        for i in idxs.flatten():
            # extract bounding box coordinates
            x, y = boxes[i][0], boxes[i][1]
            w, h = boxes[i][2], boxes[i][3]

            # draw the bounding box and label on the image
            color = [int(c) for c in colors[classIDs[i]]]
            cv2.rectangle(image, (x, y), (x + w, y + h), color, 2)
            text = "{}: {:.4f}".format(labels[classIDs[i]], confidences[i])
            cv2.putText(image, text, (x, y - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)

    return image


def make_prediction(net, layer_names, labels, image, confidence, threshold):
    height, width = image.shape[:2]

    # Create a blob and pass it through the model
    blob = cv2.dnn.blobFromImage(image, 1 / 255.0, (416, 416), swapRB=True, crop=False)
    net.setInput(blob)
    outputs = net.forward(layer_names)

    # Extract bounding boxes, confidences and classIDs
    boxes, confidences, classIDs = extract_boxes_confidences_classids(outputs, confidence, width, height)

    # Apply Non-Max Suppression
    idxs = cv2.dnn.NMSBoxes(boxes, confidences, confidence, threshold)

    return boxes, confidences, classIDs, idxs
if __name__ == '__main__':
    # Get the labels
    image_name = '/tpu_test/person_test.jpg'
    labels = open('/config/models/yolov4/coco.names').read().strip().split('\n')
    # Create a list of colors for the labels
    colors = np.random.randint(0, 255, size=(len(labels), 3), dtype='uint8')
    # Load weights using OpenCV
    print(f"Loading YOLOv4 model and config")
    net = cv2.dnn.readNetFromDarknet('/config/models/yolov4/yolov4.cfg', '/config/models/yolov4/yolov4.weights')
    print(f"Setting GPU as processing device")
    net.setPreferableBackend(cv2.dnn.DNN_BACKEND_CUDA)
    net.setPreferableTarget(cv2.dnn.DNN_TARGET_CUDA)
    (maj, minor, patch) = cv2.__version__.split('.')
    min_ver = int(maj + minor)
    patch = patch if patch.isnumeric() else 0
    patch_ver = int(maj + minor + patch)
    # 4.5.4 and above (@pliablepixels tracked down the exact version change
    # see https://github.com/ZoneMinder/mlapi/issues/44)
    layer_names = net.getLayerNames()
    if patch_ver >= 454:
        layer_names = [layer_names[i - 1] for i in net.getUnconnectedOutLayers()]
    else:
        layer_names = [layer_names[i[0] - 1] for i in net.getUnconnectedOutLayers()]

    image = cv2.imread(image_name)

    boxes, confidences, classIDs, idxs = make_prediction(net, layer_names, labels, image, 0.5, 0.3)
    print(f"{boxes = } - {confidences = } - {classIDs = } - {idxs = }")
