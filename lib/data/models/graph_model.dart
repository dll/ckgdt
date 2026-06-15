class GraphModel {
  final String id;
  final String title;
  final String? courseId;
  final String? graphType;
  final String? layout;

  GraphModel({
    required this.id,
    required this.title,
    this.courseId,
    this.graphType,
    this.layout,
  });

  factory GraphModel.fromMap(Map<String, dynamic> map) {
    return GraphModel(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      courseId: map['course_id'],
      graphType: map['graph_type'],
      layout: map['layout'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      if (courseId != null) 'course_id': courseId,
      'graph_type': graphType,
      'layout': layout,
    };
  }
}
