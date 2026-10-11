void main() {
  final data = {
    "input_types": ["int", "str", "bool", "array"],
    "blocks": [
      {
        "name": "image block",
        "input": [{}],
        "output": [
          {"name": "output image", "type": "array", "mandatory": true},
        ],
        "parameter": [
          {
            "name": "camera name",
            "type": "DROPDOWN",
            "value": ["camera 1", "camera 2", "camera 3"],
          },
        ],
      },
      {
        "name": "binary image",
        "input": [
          {"name": "source image", "type": "array", "mandatory": true},
        ],
        "output": [
          {"name": "output image", "type": "array", "mandatory": true},
        ],
        "parameter": [
          {"name": "Thresh max", "type": "INT", "value": null},
          {"name": "Thresh min", "type": "INT", "value": null},
        ],
      },
    ],
  };
}
