import 'dart:convert';
import 'dart:io';
import '../../../lib/features/listening/prepared_text_map.dart';
Future<void> main(List<String> args)async{
 final input=jsonDecode(await File(args.single).readAsString()) as Map;
 final cases=(input['cases']??input['occurrences']) as List;
 var checked=0;
 for(final entry in cases){
  final map=PreparedTextMap.fromSource(entry['source'] as String,sourceOffset:entry['sourceOffset'] as int);
  if(map.prepared!=entry['prepared'])throw StateError('Prepared mismatch: ${entry['id']}');
  final spans=[for(final s in map.spans){'start':s.preparedStart,'end':s.preparedEnd,'sourceStart':s.source?.start,'sourceEnd':s.source?.end,'inserted':s.inserted}];
  if(jsonEncode(spans)!=jsonEncode(entry['mapping']))throw StateError('Canonical mapping mismatch: ${entry['id']}');
  checked++;
 }
 print(jsonEncode({'occurrencesVerified':checked,'preparedAndAbsoluteMappingsIdentical':true,'g1':'not_evaluated'}));
}
