/// Türkçe liste dizimi: "A", "A ve B", "A, B ve C".
///
/// Hata özetleri ve rozetlerde kaynak adları bu kuralla birleştirilir;
/// "A ve B ve C" gibi tekrarlı bağlaçlar görülmez.
String turkishList(List<String> items) => switch (items.length) {
  0 => '',
  1 => items.single,
  2 => '${items.first} ve ${items.last}',
  _ => '${items.sublist(0, items.length - 1).join(', ')} ve ${items.last}',
};
