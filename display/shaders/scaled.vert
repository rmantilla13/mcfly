#version 440
// ScaledShader's vertex stage: one triangle over the whole colour buffer,
// handing the ShaderEffect fragment shaders the qt_TexCoord0 they expect
// (0..1 from the top left; the renderer works out which way y runs). No
// uniforms, so the fragment shader's block is the only one.

layout(location = 0) in vec2 position;
layout(location = 1) in vec2 texCoord;

layout(location = 0) out vec2 qt_TexCoord0;

void main()
{
    qt_TexCoord0 = texCoord;
    gl_Position = vec4(position, 0.0, 1.0);
}
