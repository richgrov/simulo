from ultralytics import YOLO

model = YOLO("yolo11n-pose.pt")
model.export(format="onnx")
