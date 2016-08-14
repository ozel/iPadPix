Pod::Spec.new do |s|
  s.name             = "ObjectiveAvro"
  s.version          = "0.1.0"
  s.summary          = "ObjectiveAvro is a wrapper on Avro-C, (almost) mimicking the interface of NSJSONSerialization."
  s.homepage         = "https://github.com/Movile/ObjectiveAvro"
  s.license          = 'MIT'
  s.author           = { "Marcelo Fabri" => "me@marcelofabri.com" }
  s.source           = { :git => "https://github.com/Movile/ObjectiveAvro.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/marcelofabri_'

  s.ios.deployment_target = '6.0'
  s.osx.deployment_target = '10.8'
  s.requires_arc = true

  s.source_files = 'Classes'

  s.dependency 'Avro-C', '~> 1.7.6'
end
